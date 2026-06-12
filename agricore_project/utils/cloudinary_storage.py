import cloudinary
import cloudinary.uploader
from django.conf import settings

cloudinary.config(
    cloud_name=settings.CLOUDINARY_CLOUD_NAME,
    api_key=settings.CLOUDINARY_API_KEY,
    api_secret=settings.CLOUDINARY_API_SECRET,
    secure=True,
)


def upload_file(file_obj, folder="general", filename=None):
    options = {"folder": folder, "resource_type": "auto"}
    if filename:
        options["public_id"] = filename
    result = cloudinary.uploader.upload(file_obj, **options)
    return result["secure_url"], result["public_id"]
