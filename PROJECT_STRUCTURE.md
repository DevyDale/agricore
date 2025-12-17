# AgriCore Project Structure

## Git Repository Information

**Repository Location**: `/Users/yigamatthew/Downloads/projects/agricore`

### Branch Strategy

This project uses a **two-branch workflow**:

#### Main Branch (`main`)
- **Purpose**: Stable, production-ready code
- **Updates**: Only receives tested, verified code from `dev` branch
- **Protection**: Should not be directly edited; all changes come through `dev`
- **Use Case**: Deployment, releases, stable snapshots

#### Development Branch (`dev`)
- **Purpose**: Active development and AI-assisted modifications
- **Updates**: Claude AI and developers work on this branch
- **Testing**: All new features tested here before merging to `main`
- **Use Case**: Feature development, bug fixes, AI modifications

### Git Workflow Commands

```bash
# Check current branch
git branch

# Switch to dev for development
git checkout dev

# Switch to main to view stable code
git checkout main

# After making changes on dev
git add .
git commit -m "Description of changes"

# When dev is stable, merge to main
git checkout main
git merge dev

# View commit history
git log --oneline --graph --all
```

## Project Architecture

### Flutter Frontend Structure

```
lib/                          # Flutter application source
├── main.dart                 # Application entry point
└── (to be expanded)

android/                      # Android platform-specific code
ios/                          # iOS platform-specific code
web/                          # Web platform code
linux/                        # Linux desktop code
macos/                        # macOS desktop code
windows/                      # Windows desktop code

test/                         # Flutter widget tests
pubspec.yaml                  # Flutter dependencies
```

### Django Backend Structure

```
agricore_project/             # Django REST API Backend
├── manage.py                 # Django management script
├── requirements.txt          # Python dependencies
│
├── agricore_project/         # Project configuration
│   ├── settings.py          # Django settings
│   ├── urls.py              # Main URL routing
│   ├── asgi.py              # ASGI configuration (WebSockets)
│   ├── wsgi.py              # WSGI configuration
│   └── celery.py            # Celery task queue config
│
├── accounts/                 # User management & authentication
│   ├── models.py            # User models, roles, profiles
│   ├── api/                 # REST API endpoints
│   └── migrations/
│
├── ai/                       # AI-powered features
│   ├── models.py            # AI interaction models
│   ├── tasks.py             # Celery tasks for AI
│   └── api/
│
├── analytics/                # Data analytics & reporting
│   ├── models.py            # Analytics data models
│   └── api/
│
├── communications/           # Real-time messaging
│   ├── models.py            # Message, conversation models
│   ├── consumers.py         # WebSocket consumers
│   ├── routing.py           # WebSocket routing
│   └── api/
│
├── crops/                    # Crop management
│   ├── models.py            # Crop, planting models
│   └── api/
│
├── farms/                    # Farm management
│   ├── models.py            # Farm, field, environment models
│   ├── signals.py           # Django signals
│   └── api/
│
├── inventory/                # Inventory tracking
│   ├── models.py            # Stock, equipment models
│   └── api/
│
├── livestock/                # Livestock management
│   ├── models.py            # Animal, health record models
│   └── api/
│
├── marketplace/              # Agricultural marketplace
│   ├── models.py            # Product, store, order models
│   ├── tests/               # Marketplace tests
│   └── api/
│
├── produce/                  # Produce management
│   ├── models.py            # Harvest, collection models
│   └── serializers.py
│
├── workforce/                # Workforce management
│   ├── models.py            # Worker, job posting models
│   └── api/
│
├── utils/                    # Shared utilities
│   └── supabase_storage.py  # File storage
│
├── static/                   # Static files (CSS, JS, images)
├── templates/                # HTML templates
└── myenv/                    # Python virtual environment (ignored by git)
```

## Technology Stack

### Backend Dependencies (requirements.txt)
- **django** - Web framework
- **djangorestframework** - REST API
- **drf-nested-routers** - Nested API routes
- **django-environ** - Environment configuration
- **django-cors-headers** - CORS handling
- **Pillow** - Image processing
- **channels** - WebSocket support
- **channels_redis** - Redis channel layer
- **redis** - Redis client
- **celery** - Async task queue
- **django-celery-beat** - Periodic tasks
- **openai** - OpenAI API
- **groq** - Groq AI API
- **PyPDF2** - PDF processing
- **python-magic** - File type detection
- **psycopg2-binary** - PostgreSQL adapter
- **djangorestframework-simplejwt** - JWT authentication
- **gunicorn** - Production server
- **dj-database-url** - Database URL parsing
- **python-dotenv** - Environment variables
- **whitenoise** - Static file serving
- **requests** - HTTP library

### Frontend Dependencies (pubspec.yaml)
- **flutter** - Flutter SDK
- **cupertino_icons** - iOS-style icons
- **flutter_lints** - Code linting

## Key Files

### Configuration Files
- [.gitignore](.gitignore) - Git ignore rules
- [analysis_options.yaml](analysis_options.yaml) - Dart analysis config
- [pubspec.yaml](pubspec.yaml) - Flutter dependencies
- [agricore_project/requirements.txt](agricore_project/requirements.txt) - Python dependencies

### Documentation
- [README.md](README.md) - Main project documentation
- [DIGITAL_STORE_SETUP.md](DIGITAL_STORE_SETUP.md) - Digital store feature docs
- [IMPLEMENTATION_COMPLETE.md](IMPLEMENTATION_COMPLETE.md) - Implementation status
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - This file

### Scripts
- [setup_digital_store.sh](setup_digital_store.sh) - Store setup script
- [agricore_project/manage.py](agricore_project/manage.py) - Django management

## Development Setup

### Prerequisites
- Flutter SDK 3.9.2+
- Python 3.8+
- PostgreSQL 12+ (production) or SQLite (development)
- Redis (for Channels & Celery)

### Backend Setup
```bash
cd agricore_project
python -m venv myenv
source myenv/bin/activate  # On Windows: myenv\Scripts\activate
pip install -r requirements.txt
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

### Frontend Setup
```bash
flutter pub get
flutter run
```

## Claude AI Development Guidelines

When working with this project:

1. **Always work on the `dev` branch**
   ```bash
   git checkout dev
   ```

2. **Make atomic commits with clear messages**
   ```bash
   git add <specific-files>
   git commit -m "feat: Add feature X to module Y"
   ```

3. **Test changes before committing**
   - Run Django tests: `python manage.py test`
   - Run Flutter tests: `flutter test`

4. **Follow the existing code structure**
   - Django apps in `agricore_project/`
   - Flutter code in `lib/`
   - Keep models, serializers, and views organized

5. **Document significant changes**
   - Update relevant .md files
   - Add code comments for complex logic

6. **When ready to merge to main**
   ```bash
   git checkout main
   git merge dev
   git checkout dev  # Return to dev for continued work
   ```

## Current Status

✅ Git repository initialized
✅ Main branch created with stable code
✅ Dev branch created for active development
✅ All project files committed
✅ README updated with comprehensive documentation
✅ .gitignore configured for Python and Flutter
✅ Project structure clearly defined
✅ Django backend properly integrated
✅ Flutter frontend structure in place

## Next Steps

1. Set up remote repository (GitHub/GitLab) if needed
2. Configure Django settings for production
3. Set up environment variables (.env file)
4. Begin feature development on `dev` branch
5. Implement CI/CD pipeline if needed

## Notes

- The `myenv/` virtual environment is ignored by git
- All `__pycache__/` and `.pyc` files are excluded
- Celery beat schedule files are excluded
- Platform-specific build artifacts are excluded
- Database files (*.sqlite3) are excluded
