from setuptools import setup, find_packages

setup(
    name="ml-service",
    version="1.0.0",
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    python_requires=">=3.9",
    install_requires=[
        "fastapi==0.104.1",
        "uvicorn[standard]==0.24.0",
        "mlflow==2.4.1",
        "scikit-learn==1.3.2",
        "pandas==2.1.3",
        "numpy==1.26.2",
        "xgboost==2.0.0",
        "redis==5.0.1",
        "boto3==1.34.0",
    ],
    extras_require={
        "dev": [
            "pytest==7.4.3",
            "pytest-cov==4.1.0",
            "black==23.11.0",
            "flake8==6.1.0",
            "mypy==1.7.0",
        ]
    },
    entry_points={
        "console_scripts": [
            "ml-service=api.app:main",
        ],
    },
)
