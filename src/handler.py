import time
import runpod
import requests
from requests.adapters import HTTPAdapter, Retry
import os
import base64

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


def get_presigned_url(file_path):
    VOLUME_ID = os.environ.get("RUNPOD_VOLUME_ID")
    RUNPOD_API_KEY = os.environ.get("RUNPOD_API_KEY")
    if not VOLUME_ID or not RUNPOD_API_KEY:
        # For test/build step, return a dummy URL
        return f"https://dummy-url-for-testing/{file_path}"
    RUNPOD_API_URL = f"https://api.runpod.io/v2/volume/{VOLUME_ID}/presigned-url"
    headers = {"Authorization": f"Bearer {RUNPOD_API_KEY}"}
    data = {"path": file_path, "operation": "read"}
    response = requests.post(RUNPOD_API_URL, json=data, headers=headers)
    response.raise_for_status()
    return response.json()["url"]


# ---------------------------------------------------------------------------- #
#                                RunPod Handler                                #
# ---------------------------------------------------------------------------- #
def handler(event):
    """
    This is the handler function that will be called by the serverless.
    """
    endpoint = event.get("endpoint", "txt2img")
    result = run_inference(event["input"], endpoint=endpoint)

    # Save images to /runpod-volume/output and generate pre-signed URLs by idx
    output_dir = "/runpod-volume/output"
    os.makedirs(output_dir, exist_ok=True)
    image_urls = []
    for idx, img_b64 in enumerate(result.get("images", [])):
        img_path = f"output/image_{idx}.png"  # relative to /runpod-volume
        abs_img_path = os.path.join("/runpod-volume", img_path)
        with open(abs_img_path, "wb") as f:
            f.write(base64.b64decode(img_b64))
        url = get_presigned_url(img_path)
        image_urls.append(url)

    return {"output_urls": image_urls}


if __name__ == "__main__":
    wait_for_service(url=f'{LOCAL_URL}/sd-models')
    print("WebUI API Service is ready. Starting RunPod Serverless...")
    runpod.serverless.start({"handler": handler})