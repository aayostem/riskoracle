# src/python/feature-service/src/cache/advanced_cache.py
from typing import Any, Dict, List, Optional
import redis
import json
import hashlib
import pickle
from datetime import datetime, timedelta
import asyncio
from dataclasses import dataclass
import logging
import numpy as np

logger = logging.getLogger(__name__)

@dataclass
class CacheConfig:
    """Cache configuration"""
    ttl_seconds: int = 3600  # 1 hour default TTL
    max_size_mb: int = 1000  # 1GB max cache size
    compression_enabled: bool = True
    predictive_prefetch: bool = True
    tiered_cache: bool = True

class TieredCache:
    """Advanced tiered caching strategy"""
    
    def __init__(self, config: CacheConfig):
        self.config = config
        
        # L0: In-memory cache (LRU)
        self.l0_cache = {}
        self.l0_size = 0
        
        # L1: Redis cluster (hot data)
        self.redis_client = redis.RedisCluster(
            host='redis.ml-platform.svc.cluster.local',
            port=6379,
            decode_responses=False,
            max_connections=50,
            socket_keepalive=True
        )
        
        # L2: Disk cache (warm data)
        self.disk_cache_path = "/var/cache/features"
        
        # Statistics
        self.stats = {
            'hits': {'l0': 0, 'l1': 0, 'l2': 0},
            'misses': 0,
            'writes': 0,
            'evictions': 0
        }
        
        # Predictive prefetch model
        self.prefetch_model = self._init_prefetch_model()
        
    def _init_prefetch_model(self):
        """Initialize predictive prefetch model"""
        # Simple Markov chain for access pattern prediction
        return {
            'transition_matrix': {},
            'access_patterns': {},
            'last_access': {}
        }
    
    def _generate_cache_key(self, entity_type: str, entity_id: str, features: List[str]) -> str:
        """Generate deterministic cache key"""
        key_data = f"{entity_type}:{entity_id}:{','.join(sorted(features))}"
        return hashlib.sha256(key_data.encode()).hexdigest()
    
    async def get(self, entity_type: str, entity_id: str, features: List[str]) -> Optional[Dict]:
        """Get features from cache with tiered lookup"""
        cache_key = self._generate_cache_key(entity_type, entity_id, features)
        
        # L0: In-memory cache
        if cache_key in self.l0_cache:
            self.stats['hits']['l0'] += 1
            logger.debug(f"L0 cache hit for {cache_key}")
            return self.l0_cache[cache_key]
        
        # L1: Redis cache
        try:
            cached_data = self.redis_client.get(cache_key)
            if cached_data:
                self.stats['hits']['l1'] += 1
                data = pickle.loads(cached_data)
                
                # Promote to L0 cache
                self.l0_cache[cache_key] = data
                self.l0_size += len(cached_data)
                
                # Evict if necessary
                self._evict_l0_if_needed()
                
                logger.debug(f"L1 cache hit for {cache_key}")
                return data
        except redis.RedisError as e:
            logger.warning(f"Redis error: {e}")
        
        # L2: Disk cache (simplified - in production would use actual disk cache)
        # For now, treat as miss
        
        self.stats['misses'] += 1
        logger.debug(f"Cache miss for {cache_key}")
        
        # Trigger predictive prefetch
        if self.config.predictive_prefetch:
            asyncio.create_task(self._predictive_prefetch(entity_type, entity_id))
        
        return None
    
    async def set(self, entity_type: str, entity_id: str, features: List[str], data: Dict):
        """Set features in cache with tiered storage"""
        cache_key = self._generate_cache_key(entity_type, entity_id, features)
        
        # Update predictive model
        self._update_prefetch_model(entity_type, entity_id, features)
        
        # L0: In-memory cache
        serialized_data = pickle.dumps(data)
        data_size = len(serialized_data)
        
        if data_size < 1024 * 1024:  # Only cache if < 1MB
            self.l0_cache[cache_key] = data
            self.l0_size += data_size
            self._evict_l0_if_needed()
        
        # L1: Redis cache with compression if enabled
        try:
            if self.config.compression_enabled and data_size > 1024:  # Compress if > 1KB
                import zlib
                compressed_data = zlib.compress(serialized_data)
                if len(compressed_data) < data_size * 0.8:  # Only store if compression saves > 20%
                    serialized_data = compressed_data
            
            self.redis_client.setex(
                cache_key,
                self.config.ttl_seconds,
                serialized_data
            )
            self.stats['writes'] += 1
        except redis.RedisError as e:
            logger.warning(f"Redis write error: {e}")
        
        logger.debug(f"Cached data for {cache_key}")
    
    def _evict_l0_if_needed(self):
        """Evict from L0 cache if size limit exceeded"""
        max_size_bytes = self.config.max_size_mb * 1024 * 1024
        
        while self.l0_size > max_size_bytes and self.l0_cache:
            # Simple LRU eviction (in production use proper LRU)
            key_to_evict = next(iter(self.l0_cache))
            evicted_size = len(pickle.dumps(self.l0_cache[key_to_evict]))
            del self.l0_cache[key_to_evict]
            self.l0_size -= evicted_size
            self.stats['evictions'] += 1
    
    def _update_prefetch_model(self, entity_type: str, entity_id: str, features: List[str]):
        """Update predictive prefetch model"""
        entity_key = f"{entity_type}:{entity_id}"
        now = datetime.now()
        
        # Record access
        if entity_key in self.prefetch_model['last_access']:
            last_access = self.prefetch_model['last_access'][entity_key]
            time_diff = (now - last_access).total_seconds()
            
            # Update transition probabilities
            if time_diff < 60:  # Accesses within 60 seconds
                if 'last_entity' in self.prefetch_model:
                    last_entity = self.prefetch_model['last_entity']
                    if last_entity not in self.prefetch_model['transition_matrix']:
                        self.prefetch_model['transition_matrix'][last_entity] = {}
                    
                    self.prefetch_model['transition_matrix'][last_entity][entity_key] = \
                        self.prefetch_model['transition_matrix'][last_entity].get(entity_key, 0) + 1
        
        self.prefetch_model['last_access'][entity_key] = now
        self.prefetch_model['last_entity'] = entity_key
    
    async def _predictive_prefetch(self, entity_type: str, entity_id: str):
        """Predictively prefetch likely next features"""
        entity_key = f"{entity_type}:{entity_id}"
        
        if entity_key in self.prefetch_model['transition_matrix']:
            transitions = self.prefetch_model['transition_matrix'][entity_key]
            
            # Find most likely next entities
            likely_next = sorted(transitions.items(), key=lambda x: x[1], reverse=True)[:3]
            
            for next_entity, count in likely_next:
                # Parse entity info
                parts = next_entity.split(':')
                if len(parts) == 2:
                    next_entity_type, next_entity_id = parts
                    
                    # Prefetch common features for this entity type
                    common_features = self._get_common_features(next_entity_type)
                    
                    if common_features:
                        # In production, this would trigger async prefetch
                        logger.info(f"Predictive prefetch for {next_entity_type}:{next_entity_id}")
    
    def _get_common_features(self, entity_type: str) -> List[str]:
        """Get common features for entity type"""
        # In production, this would come from feature metadata
        common_features = {
            'customer': ['avg_transaction_amount', 'transaction_frequency_7d', 'fraud_rate'],
            'transaction': ['amount', 'time_of_day', 'is_weekend'],
            'merchant': ['merchant_fraud_rate', 'total_transactions']
        }
        
        return common_features.get(entity_type, [])
    
    def get_stats(self) -> Dict:
        """Get cache statistics"""
        total_hits = sum(self.stats['hits'].values())
        total_accesses = total_hits + self.stats['misses']
        
        return {
            'hit_rate': total_hits / total_accesses if total_accesses > 0 else 0,
            'hit_breakdown': self.stats['hits'],
            'misses': self.stats['misses'],
            'writes': self.stats['writes'],
            'evictions': self.stats['evictions'],
            'l0_size_mb': self.l0_size / (1024 * 1024),
            'l0_items': len(self.l0_cache)
        }

class FeatureCacheManager:
    """Manager for feature caching with advanced strategies"""
    
    def __init__(self):
        self.cache = TieredCache(CacheConfig())
        self.request_batching = {}
        self.batch_lock = asyncio.Lock()
        
    async def get_features_batch(self, requests: List[Dict]) -> List[Optional[Dict]]:
        """Get features in batch with deduplication"""
        # Group by cache key for deduplication
        cache_keys = []
        key_to_request = {}
        
        for req in requests:
            cache_key = self.cache._generate_cache_key(
                req['entity_type'],
                req['entity_id'],
                req['features']
            )
            cache_keys.append(cache_key)
            key_to_request[cache_key] = req
        
        # Check cache for all keys
        cached_results = {}
        missing_keys = []
        
        for cache_key in cache_keys:
            # Simplified - in production would batch Redis calls
            result = await self.cache.get(
                key_to_request[cache_key]['entity_type'],
                key_to_request[cache_key]['entity_id'],
                key_to_request[cache_key]['features']
            )
            
            if result is not None:
                cached_results[cache_key] = result
            else:
                missing_keys.append(cache_key)
        
        # Fetch missing keys from source (in production)
        fetched_results = {}
        if missing_keys:
            # Batch fetch from feature store
            fetched_results = await self._batch_fetch_from_source(missing_keys, key_to_request)
        
        # Combine results
        results = []
        for cache_key in cache_keys:
            if cache_key in cached_results:
                results.append(cached_results[cache_key])
            elif cache_key in fetched_results:
                results.append(fetched_results[cache_key])
            else:
                results.append(None)
        
        return results
    
    async def _batch_fetch_from_source(self, missing_keys: List[str], key_to_request: Dict) -> Dict:
        """Batch fetch missing features from source"""
        # Group by entity type for efficient fetching
        requests_by_type = {}
        for cache_key in missing_keys:
            req = key_to_request[cache_key]
            entity_type = req['entity_type']
            
            if entity_type not in requests_by_type:
                requests_by_type[entity_type] = []
            
            requests_by_type[entity_type].append(req)
        
        # Fetch from each source
        all_results = {}
        
        for entity_type, type_requests in requests_by_type.items():
            # In production, this would call the appropriate data source
            # For now, return empty results
            for req in type_requests:
                cache_key = self.cache._generate_cache_key(
                    req['entity_type'],
                    req['entity_id'],
                    req['features']
                )
                # Simulate fetched data
                fetched_data = {
                    'entity_id': req['entity_id'],
                    'features': {f: 0.0 for f in req['features']},
                    'timestamp': datetime.now().isoformat()
                }
                
                all_results[cache_key] = fetched_data
                
                # Cache the result
                await self.cache.set(
                    req['entity_type'],
                    req['entity_id'],
                    req['features'],
                    fetched_data
                )
        
        return all_results