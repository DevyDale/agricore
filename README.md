# AgriCore - Agricultural Management System

A comprehensive agricultural management platform combining Flutter mobile frontend with Django REST backend.

## Project Architecture

This is a **hybrid Flutter + Django project** with the following structure:

```
agricore/
├── agricore_project/     # Django REST API Backend
│   ├── accounts/         # User authentication & management
│   ├── ai/              # AI-powered features
│   ├── analytics/       # Data analytics
│   ├── communications/  # Real-time messaging (WebSockets)
│   ├── crops/           # Crop management
│   ├── farms/           # Farm management
│   ├── inventory/       # Inventory tracking
│   ├── livestock/       # Livestock management
│   ├── marketplace/     # Agricultural marketplace
│   ├── produce/         # Produce management
│   └── workforce/       # Workforce management
├── lib/                 # Flutter mobile app source
├── android/            # Android platform code
├── ios/                # iOS platform code
├── web/                # Web platform code
├── linux/              # Linux platform code
├── macos/              # macOS platform code
└── windows/            # Windows platform code
```

## Technology Stack

### Backend (Django)
- **Framework**: Django + Django REST Framework
- **Database**: PostgreSQL (production) / SQLite (development)
- **Real-time**: Django Channels + Redis
- **Task Queue**: Celery + Redis
- **AI Integration**: OpenAI API, Groq
- **Authentication**: JWT (djangorestframework-simplejwt)

### Frontend (Flutter)
- **Framework**: Flutter 3.9.2+
- **Language**: Dart
- **UI**: Material Design / Cupertino widgets

## Prerequisites

- **Flutter SDK**: 3.9.2 or higher
- **Python**: 3.8 or higher
- **PostgreSQL**: 12 or higher (production)
- **Redis**: Latest stable (for Channels & Celery)
- **Git**: For version control

## Quick Start

### Backend Setup (Django)

1. Navigate to Django project:
   ```bash
   cd agricore_project
   ```

2. Create virtual environment:
   ```bash
   python -m venv myenv
   source myenv/bin/activate  # On Windows: myenv\Scripts\activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Set up environment variables:
   ```bash
   cp .env.example .env  # Create from example
   # Edit .env with your configuration
   ```

5. Run migrations:
   ```bash
   python manage.py migrate
   ```

6. Create superuser:
   ```bash
   python manage.py createsuperuser
   ```

7. Start development server:
   ```bash
   python manage.py runserver
   ```

### Frontend Setup (Flutter)

1. From project root:
   ```bash
   flutter pub get
   ```

2. Run the app:
   ```bash
   flutter run
   ```

## Git Workflow

This project uses a **two-branch strategy**:

- **`main`** - Stable production-ready code
- **`dev`** - Development branch for AI/Claude updates and testing

### Branch Usage

```bash
# Work on development branch
git checkout dev

# Make changes, test, commit
git add .
git commit -m "Description of changes"

# When stable, merge to main
git checkout main
git merge dev
```

## API Documentation

Backend API runs at: `http://localhost:8000/api/`

Key endpoints:
- `/api/accounts/` - User management
- `/api/farms/` - Farm operations
- `/api/crops/` - Crop management
- `/api/marketplace/` - Marketplace features
- `/api/analytics/` - Analytics data

## Development Guidelines

1. **Backend changes**: Work in `agricore_project/`
2. **Frontend changes**: Work in `lib/`
3. **Always commit to `dev` branch first**
4. **Test thoroughly before merging to `main`**
5. **Follow existing code patterns and structure**

## Additional Documentation

- [Digital Store Setup](DIGITAL_STORE_SETUP.md)
- [Implementation Status](IMPLEMENTATION_COMPLETE.md)

## Contributing

1. Create feature branch from `dev`
2. Make your changes
3. Test thoroughly
4. Submit pull request to `dev` branch

## License

Private project - All rights reserved
