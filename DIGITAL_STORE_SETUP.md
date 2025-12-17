# Digital Store - Backend Integration Setup

## What Was Added

### New Models (marketplace/models.py)
1. **Advertisement** - Store advertisements with customizable design, pricing, and analytics
2. **StoreReview** - Customer reviews for stores with ratings
3. **ProductReview** - Customer reviews for products with ratings
4. **PaymentCard** - Secure payment card storage (only last 4 digits stored)

### New API Endpoints
All endpoints require authentication (Bearer token).

#### Advertisements
- `GET /api/advertisements/` - List all advertisements for user's stores
- `GET /api/advertisements/?store=<id>` - Filter by store
- `POST /api/advertisements/` - Create new advertisement (with image/audio upload)
- `GET /api/advertisements/<id>/` - Get advertisement details
- `PATCH /api/advertisements/<id>/` - Update advertisement
- `DELETE /api/advertisements/<id>/` - Delete advertisement
- `POST /api/advertisements/<id>/track_impression/` - Track ad view
- `POST /api/advertisements/<id>/track_click/` - Track ad click

#### Store Reviews
- `GET /api/store-reviews/?store=<id>` - Get reviews for a store
- `POST /api/store-reviews/` - Create store review
- `PATCH /api/store-reviews/<id>/` - Update review
- `DELETE /api/store-reviews/<id>/` - Delete review

#### Product Reviews
- `GET /api/product-reviews/?product=<id>` - Get reviews for a product
- `POST /api/product-reviews/` - Create product review
- `PATCH /api/product-reviews/<id>/` - Update review
- `DELETE /api/product-reviews/<id>/` - Delete review

#### Payment Cards
- `GET /api/payment-cards/` - List user's saved cards
- `POST /api/payment-cards/` - Add new card
- `PATCH /api/payment-cards/<id>/` - Update card (e.g., set default)
- `DELETE /api/payment-cards/<id>/` - Remove card

### Frontend Features (digital_store.html)

#### 1. Advertisement Creation
- **Location**: Create Advertisement tab in sidebar
- **Features**:
  - Live preview of ad design
  - Font family and size customization
  - Background and text color pickers
  - Image upload with fit/position/brightness controls
  - Audio/sound upload
  - Duration selection (1 day/₦500, 1 week/₦3,000, 1 month/₦10,000)
  - Real-time preview updates
- **Backend Integration**: ✅ Fully integrated with FormData for file uploads

#### 2. Payment Card Management
- **Location**: Wallet section
- **Features**:
  - Add new cards with cardholder name, card number, expiry, CVV
  - List all saved cards (shows last 4 digits only)
  - Set default card
  - Remove cards
  - Card brand detection (Visa, Mastercard, Amex)
- **Backend Integration**: ✅ Fully integrated with secure storage

#### 3. Store & Product Reviews
- **Location**: Ratings & Reviews tab
- **Features**:
  - Display store reviews with ratings
  - Display product reviews with ratings
  - Rating distribution bars
  - Average rating calculation
- **Backend Integration**: ✅ Fully integrated

## Setup Instructions

### 1. Install Dependencies
```bash
cd /Users/yigamatthew/Downloads/projects/agricore
pip install Pillow drf-nested-routers
```

### 2. Run Migrations
```bash
cd agricore_project
python3 manage.py migrate marketplace
```

### 3. Create Media Directory
```bash
mkdir -p agricore_project/media/advertisements/audio
```

### 4. Start Development Server
```bash
python3 manage.py runserver
```

## Testing the Features

### Test Advertisement Creation
1. Login to the app
2. Navigate to Digital Store page
3. Click "Create Advertisement" in sidebar
4. Fill in:
   - Title: "Summer Sale!"
   - Description: "50% off all products"
   - Upload an image (JPG/PNG)
   - Choose colors using color pickers
   - Select font family and sizes
   - Optionally upload audio
   - Select duration (1 day, 1 week, or 1 month)
5. Watch live preview update in real-time
6. Click "Launch Advertisement"
7. Check database or Django admin to verify creation

### Test Payment Card Management
1. Navigate to Wallet section in Digital Store
2. Fill in card form:
   - Cardholder Name: "John Doe"
   - Card Number: "4532123456789012" (Visa test card)
   - Expiry: "12/25"
   - CVV: "123"
3. Click "Add Card"
4. Card should appear in "Your Cards" section with last 4 digits
5. Try setting as default
6. Try removing the card

### Test Reviews (Backend Ready)
Store and product reviews are backend-ready. To test:
1. Use API endpoint: `POST /api/store-reviews/`
   ```json
   {
     "store": 1,
     "rating": 5,
     "comment": "Great store!"
   }
   ```
2. Reviews will appear in Ratings & Reviews tab

## Security Notes

### Payment Cards
- **CVV is NEVER stored** - only used for validation during card addition
- Only last 4 digits of card number are stored
- Card numbers are detected and masked automatically
- In production, integrate with payment gateway (Stripe, Paystack) for tokenization

### File Uploads
- Images stored in `media/advertisements/`
- Audio files stored in `media/advertisements/audio/`
- File validation recommended in production (size, type)
- Consider CDN for production

## Admin Panel Access

All new models are registered in Django admin:
1. Go to http://127.0.0.1:8000/admin/
2. Login with superuser credentials
3. Navigate to:
   - Marketplace > Advertisements
   - Marketplace > Store Reviews
   - Marketplace > Product Reviews
   - Marketplace > Payment Cards

## API Authentication

All endpoints require JWT Bearer token:
```javascript
headers: {
  'Authorization': `Bearer ${access_token}`
}
```

Token is stored in localStorage as 'access_token' after login.

## File Upload Example (Advertisement)

```javascript
const formData = new FormData();
formData.append('store', storeId);
formData.append('title', 'My Ad');
formData.append('image', imageFile); // File from input[type="file"]
formData.append('audio', audioFile); // File from input[type="file"]
// ... other fields

fetch('/api/advertisements/', {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${token}` },
  body: formData // Don't set Content-Type, browser sets it automatically with boundary
});
```

## Database Schema

### Advertisement Table
- store (FK to Store)
- title, description
- image (ImageField)
- background_color, text_color
- cta_text, link_url
- font_family, title_font_size, description_font_size
- image_fit, image_position, image_brightness
- audio (FileField)
- duration_days, price_paid
- is_active, start_date, end_date
- impressions, clicks
- created_at, updated_at

### StoreReview Table
- store (FK to Store)
- user (FK to CustomUser)
- rating (Integer)
- comment (Text)
- Unique constraint: (store, user)

### ProductReview Table
- product (FK to Product)
- user (FK to CustomUser)
- rating (Integer)
- comment (Text)
- Unique constraint: (product, user)

### PaymentCard Table
- user (FK to CustomUser)
- cardholder_name
- card_number_last4 (only last 4 digits!)
- card_brand
- expiry_month, expiry_year
- is_default (Boolean)

## Next Steps

1. ✅ Run migrations
2. ✅ Test all features through the UI
3. 🔄 Add form validation on frontend
4. 🔄 Integrate payment gateway for real card processing
5. 🔄 Add image compression for advertisements
6. 🔄 Implement advertisement scheduling/activation
7. 🔄 Add email notifications for reviews
8. 🔄 Create analytics dashboard for ad performance

## Troubleshooting

### "No module named 'PIL'"
Run: `pip install Pillow`

### "MEDIA_URL not serving files"
- Check settings.py has MEDIA_URL and MEDIA_ROOT
- Check urls.py has static() configuration
- Only works with DEBUG=True in development

### "Unauthorized" errors
- Check localStorage has 'access_token'
- Token might be expired, re-login

### Migration errors
```bash
python3 manage.py makemigrations marketplace
python3 manage.py migrate
```

## Summary

All digital_store.html features are now fully functional and integrated with Django backend:
- ✅ Advertisement creation with file uploads
- ✅ Payment card management
- ✅ Store and product reviews
- ✅ Live preview for ad design
- ✅ Secure card storage
- ✅ Complete CRUD operations
- ✅ Admin panel integration
- ✅ JWT authentication
