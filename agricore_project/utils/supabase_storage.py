# utils/supabase_storage.py
from supabase import create_client, Client
from django.conf import settings
import uuid

# Initialize Supabase client
supabase: Client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)

def upload_file(file_obj, folder="general", filename=None):
    """
    Uploads a file to Supabase Storage and returns its public URL and storage path.
    """
    if not filename:
        filename = f"{uuid.uuid4()}_{file_obj.name}"
    path = f"{folder}/{filename}"

    # Upload the file
    res = supabase.storage.from_("attachments").upload(
        path=path,
        file=file_obj.read(),
        content_type=file_obj.content_type,  # new API: use content_type param
        upsert=True  # overwrite if exists
    )

    # Check for errors
    if res.get("error"):
        raise Exception(f"Upload failed: {res['error']}")

    # Get public URL
    public_url_res = supabase.storage.from_("attachments").get_public_url(path)
    public_url = public_url_res.get("public_url")
    
    return public_url, path