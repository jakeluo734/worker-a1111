import time
import runpod
import requests
from requests.adapters import HTTPAdapter, Retry
import os
import base64
import boto3
from botocore.client import Config
import mimetypes
import random
import string
import hashlib
from pathlib import Path

LOCAL_URL = "http://127.0.0.1:3000/sdapi/v1"

automatic_session = requests.Session()
retries = Retry(total=10, backoff_factor=0.1, status_forcelist=[502, 503, 504])
automatic_session.mount('http://', HTTPAdapter(max_retries=retries))

# ---------------------------------------------------------------------------- #
#                              Automatic Functions                             #
# ---------------------------------------------------------------------------- #
def wait_for_service(url):
    """
    Check if the service is ready to receive requests.
    """
    retries = 0

    while True:
        try:
            requests.get(url, timeout=120)
            return
        except requests.exceptions.RequestException:
            retries += 1

            # Only log every 15 retries so the logs don't get spammed
            if retries % 15 == 0:
                print("Service not ready yet. Retrying...")
        except Exception as err:
            print("Error: ", err)

        time.sleep(0.2)

def run_inference(inference_request, endpoint="txt2img"):
    """
    Run inference on a request for the specified endpoint.
    """
    response = automatic_session.post(url=f'{LOCAL_URL}/{endpoint}',
                                      json=inference_request, timeout=600)
    return response.json()

def upload_file_to_uploadthing(file_path):
    uploadthing_api_key = os.getenv('UPLOADTHING_API_KEY')
    if not uploadthing_api_key:
        # For test/build step, return a dummy URL
        return f"https://dummy-uploadthing-url-for-testing/{os.path.basename(file_path)}"
    file_path = Path(file_path)
    file_name = file_path.name
    file_extension = file_path.suffix
    random_string = ''.join(random.choices(string.ascii_letters + string.digits, k=8))
    md5_hash = hashlib.md5(random_string.encode()).hexdigest()
    new_file_name = f"{md5_hash}{file_extension}"
    file_size = file_path.stat().st_size
    file_type, _ = mimetypes.guess_type(str(file_path))

    with open(file_path, "rb") as file:
        file_content = file.read()

    file_info = {"name": new_file_name, "size": file_size, "type": file_type}
    headers = {"x-uploadthing-api-key": uploadthing_api_key}
    data = {
        "contentDisposition": "inline",
        "acl": "public-read",
        "files": [file_info],
    }

    # Get presigned URL
    presigned_response = requests.post(
        "https://api.uploadthing.com/v6/uploadFiles",
        headers=headers,
        json=data,
    )
    presigned_response.raise_for_status()
    presigned = presigned_response.json()["data"][0]
    upload_url = presigned["url"]
    fields = presigned["fields"]

    # Perform actual upload
    files = {"file": file_content}
    upload_response = requests.post(upload_url, data=fields, files=files)
    upload_response.raise_for_status()

    return presigned['fileUrl']

# ---------------------------------------------------------------------------- #
#                                RunPod Handler                                #
# ---------------------------------------------------------------------------- #
def handler(event):
    """
    This is the handler function that will be called by the serverless.
    """
    print(f"[DEBUG] Incoming event: {event}")
    # Extract endpoint from event['input'], defaulting to 'img2img' if not present
    endpoint = event.get("input", {}).get("endpoint", "txt2img")
    print(f"[DEBUG] Using endpoint: {endpoint}")
    result = run_inference(event["input"], endpoint=endpoint)

    # Save images to /runpod-volume/output and upload to UploadThing
    output_dir = "/runpod-volume/output"
    os.makedirs(output_dir, exist_ok=True)
    image_urls = []
    for idx, img_b64 in enumerate(result.get("images", [])):
        img_path = f"output/image_{idx}.png"  # relative to /runpod-volume
        abs_img_path = os.path.join("/runpod-volume", img_path)
        with open(abs_img_path, "wb") as f:
            f.write(base64.b64decode(img_b64))
        url = upload_file_to_uploadthing(abs_img_path)
        image_urls.append(url)

    return {
        "output_urls": image_urls,
        "parameters": result.get("parameters"),
        "info": result.get("info"),
        "endpoint": endpoint
    }

if __name__ == "__main__":
    wait_for_service(url=f'{LOCAL_URL}/sd-models')
    print("WebUI API Service is ready. Starting RunPod Serverless...")
    runpod.serverless.start({"handler": handler})