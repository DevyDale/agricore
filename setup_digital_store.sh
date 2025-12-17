#!/bin/bash

# Setup script for Digital Store Backend Integration

echo "🚀 Starting Digital Store Backend Setup..."
echo ""

# Navigate to project directory
cd "$(dirname "$0")/agricore_project"

echo "📦 Installing required packages..."
pip install Pillow drf-nested-routers

echo ""
echo "🗄️  Creating database migrations..."
python3 manage.py makemigrations marketplace

echo ""
echo "📊 Running migrations..."
python3 manage.py migrate

echo ""
echo "📁 Creating media directories..."
mkdir -p media/advertisements/audio

echo ""
echo "✅ Setup complete!"
echo ""
echo "🎯 Next steps:"
echo "  1. Run: python3 manage.py runserver"
echo "  2. Open: http://127.0.0.1:8000/digital_store.html?id=<your_store_id>"
echo "  3. Test advertisement creation, card management, and reviews!"
echo ""
echo "📚 See DIGITAL_STORE_SETUP.md for detailed documentation"
