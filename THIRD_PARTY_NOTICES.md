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
