from firebase_functions import https_fn
from firebase_admin import initialize_app, storage
from datetime import datetime
from gtts import gTTS
from PIL import Image
import math
import numpy
import base64
from moviepy.editor import AudioFileClip, ImageClip, concatenate_videoclips

initialize_app()


def zoom_in_effect(clip, zoom_ratio=0.04):
    def effect(get_frame, t):
        img = Image.fromarray(get_frame(t))
        base_size = img.size

        new_size = [
            math.ceil(img.size[0] * (1 + (zoom_ratio * t))),
            math.ceil(img.size[1] * (1 + (zoom_ratio * t)))
        ]

        new_size[0] = new_size[0] + (new_size[0] % 2)
        new_size[1] = new_size[1] + (new_size[1] % 2)

        img = img.resize(new_size, Image.LANCZOS)

        x = math.ceil((new_size[0] - base_size[0]) / 2)
        y = math.ceil((new_size[1] - base_size[1]) / 2)

        img = img.crop([
            x, y, new_size[0] - x, new_size[1] - y
        ]).resize(base_size, Image.LANCZOS)

        result = numpy.array(img)
        img.close()

        return result

    return clip.fl(effect)


@https_fn.on_call()
def get_video(req: https_fn.CallableRequest):

    images = req.data["images"]
    texts = req.data["texts"]
    for i,image_b64 in enumerate(images):
        with open(f"image_{i}.jpeg", "wb") as f:
            f.write(base64.b64decode(image_b64))
        gTTS(texts[i], tld="us").save(f"audio_{i}.mp3")
    slides = []
    for n in range(len(images)):
        audio_clip = AudioFileClip(f"audio_{n}.mp3")
        duration = audio_clip.duration
        slides.append(
            ImageClip(f"image_{n}.jpeg").set_fps(25).set_duration(duration + 1.2)
        )

        slides[n] = zoom_in_effect(slides[n], 0.04)
        slides[n] = slides[n].set_audio(audio_clip)

    video = concatenate_videoclips(slides)
    filename = f"{datetime.now()}.mp4"
    video.write_videofile(filename)
    bucket = storage.bucket()
    blob = bucket.blob(filename)
    blob.upload_from_filename(filename)
    blob.make_public()

    return {"res" : blob.public_url}