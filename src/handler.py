import time
import runpod
import requests
from requests.adapters import HTTPAdapter, Retry
import os
import base64
import boto3
from botocore.client import Config

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


def get_presigned_url_s3(file_path):
    S3_ACCESS_KEY = os.environ.get("RUNPOD_S3_ACCESS_KEY")
    S3_SECRET_KEY = os.environ.get("RUNPOD_S3_SECRET_KEY")
    VOLUME_ID = os.environ.get("RUNPOD_VOLUME_ID")
    REGION = os.environ.get("RUNPOD_S3_REGION", "EU-RO-1")  # default to EU-RO-1
    ENDPOINT_URL = os.environ.get("RUNPOD_S3_ENDPOINT", "https://s3api-eu-ro-1.runpod.io")

    if not S3_ACCESS_KEY or not S3_SECRET_KEY or not VOLUME_ID:
        # For test/build step, return a dummy URL
        return f"https://dummy-url-for-testing/{file_path}"

    s3 = boto3.client(
        "s3",
        aws_access_key_id=S3_ACCESS_KEY,
        aws_secret_access_key=S3_SECRET_KEY,
        region_name=REGION,
        endpoint_url=ENDPOINT_URL,
        config=Config(signature_version="s3v4"),
    )

    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": VOLUME_ID, "Key": file_path},
        ExpiresIn=3600  # 1 hour
    )
    return url


# ---------------------------------------------------------------------------- #
#                                RunPod Handler                                #
# ---------------------------------------------------------------------------- #
def handler(event):
    """
    This is the handler function that will be called by the serverless.
    """
    endpoint = event.get("endpoint", "txt2img")
    result = run_inference(event["input"], endpoint=endpoint)

    # Save images to /runpod-volume/output and generate pre-signed URLs
    output_dir = "/runpod-volume/output"
    os.makedirs(output_dir, exist_ok=True)
    image_urls = []
    for idx, img_b64 in enumerate(result.get("images", [])):
        img_path = f"output/image_{idx}.png"  # relative to /runpod-volume
        abs_img_path = os.path.join("/runpod-volume", img_path)
        with open(abs_img_path, "wb") as f:
            f.write(base64.b64decode(img_b64))
        url = get_presigned_url_s3(img_path)
        image_urls.append(url)

    return {"output_urls": image_urls}


if __name__ == "__main__":
    wait_for_service(url=f'{LOCAL_URL}/sd-models')
    print("WebUI API Service is ready. Starting RunPod Serverless...")
    runpod.serverless.start({"handler": handler})