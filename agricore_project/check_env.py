# test_env.py
import environ
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
env = environ.Env()
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))
print(env('SECRET_KEY'))
