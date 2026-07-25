# Third-party notices

## YOLOX-Nano person detection model

PrivacyCam includes an ONNX build of the YOLOX-Nano object detection model,
trained on the COCO object categories and used locally to locate people.

- Upstream project: https://github.com/Megvii-BaseDetection/YOLOX
- Upstream license: Apache License 2.0
- ONNX distribution: https://huggingface.co/Heliosoph/yolox-onnx
- Bundled file SHA-256: `c789161ed43c8269fcd4e67c67eeeb4e80c622da2eb296a20bc6007bd18a0b7d`

The complete Apache License 2.0 text is bundled at
`assets/legal/YOLOX_APACHE_2_LICENSE.txt`.

## YOLOv9-T license-plate detection model

PrivacyCam includes the `yolo-v9-t-384-license-plate-end2end` ONNX model from
the open-image-models project. It is used locally to locate possible vehicle
number plates.

- Upstream project: https://github.com/ankandrew/open-image-models
- Upstream license: MIT License
- Model release: https://github.com/ankandrew/open-image-models/releases/tag/assets
- Bundled file SHA-256: `888397b96d761c89db40bc9c305838e8652660f5e282c2cadebbe8d2951a77a8`

The complete MIT License text and upstream copyright notice are bundled at
`assets/legal/OPEN_IMAGE_MODELS_MIT_LICENSE.txt`.

## Pixabay onboarding video

PrivacyCam includes a modified before/after redaction demonstration derived
from "Car, Automobile, Vehicle" by Pixabay contributor MabelAmber.

- Source: https://pixabay.com/videos/car-automobile-vehicle-28132/
- Source publication date: October 21, 2019
- License: Pixabay Content License
- License summary: https://pixabay.com/service/license-summary/
- Legally binding terms: https://pixabay.com/service/terms/
- Bundled derivative:
  `assets/onboarding/video_before_after.mp4`
- Bundled derivative SHA-256:
  `e7bd4c5c7efdc85f612933a8dcee09dcd08276b8685aa48488dfb3aeaced93e6`

The video is not licensed under Apache License 2.0. It remains subject to the
Pixabay Content License and the restrictions summarized in
`assets/legal/PIXABAY_CONTENT_LICENSE_NOTICE.md`.
