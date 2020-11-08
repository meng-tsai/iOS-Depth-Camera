
# Scene Reconstruction Using iOS Dual Camera
-   Reconstructed the indoor scenes by transforming the RGB-D images into point cloud models
- Making local scene fragments, registering (aligned) different fragments, and finally integrated fragments into meshes utilizing Open3D scene reconstruction pipeline.
- Capture RGB-D images using Realsense D435

## Environment
- python 3.6.12
- jupyter-core: 4.6.3
- jupyter-notebook : 6.0.3
- numpy: 1.19.4
- [librealsense SDK](https://github.com/IntelRealSense/librealsense)
- open3d: 0.10.0
- opencv-contrib-python: 4.4.0.46

## Installation

Clone the repository with the following command:

```bash
git clone https://github.com/ashura1234/iOS-Depth-Camera.git
```
## Data Preperation and Execution
### iOS app
- Deploy the Depth Camera project to iPhone 7 or newer using Xcode
- Open the app and record the intrinsic matrix and scale shown in console
- Press the start button to start recording
- Press the start button again to stop recording
- Multiply the elements in intrinsic matrix by scale (except the 1.0)
- Save the scaled intrinsic matrix in camera_intrinsic.json
- Dump the color folder and data folder to the project folder using Xcode
- Create a new config json file
- Run main.ipynb
### Realsense Camera
- [Install Realsense camera](https://www.intelrealsense.com/get-started-depth-camera/)
- Start recording
```bash
python realsense_recorder.py --record_imgs
```
- Dump outputs to project folder
- Create a new config json
- Run main.ipynb
## Tip to recording
- Hold the camera tight and avoid and disjoint movement
- Pan the scene first then go for details
- Avoid strong source of light
- Avoid mirrors

## Result
Open scene/integrated.ply

### Input from iPhone Dual Wide Camera
![](https://github.com/ashura1234/iOS-Depth-Camera/blob/main/README_resources/iOSLivingRoom.gif?raw=true))

### Output Model

![](https://github.com/ashura1234/iOS-Depth-Camera/blob/main/README_resources/iOSLivingRoomModel.gif?raw=true)

### Input from Realsense D435 camera
![](https://github.com/ashura1234/iOS-Depth-Camera/blob/main/README_resources/RealsenseLivingRoom.gif?raw=true))

### Output Model

![](https://github.com/ashura1234/iOS-Depth-Camera/blob/main/README_resources/LivingRoomModel.gif?raw=true)

## Conclusion
iPhone stereo camera has serious flickering and precision issues. Possible reason could be the built-in filtering function creates noise, unit converting (m to mm), small distance between lenses.

Realsense camera has better depth precision, but it is still not precise enough to perform perfect loop closure. Noise is still an issue.

## TODO
- Turn off filtering in DepthCapture app and deal with nil Float
- Add support of Kinect and iPhone 12 LiDAR camera
- Fine tuning parameters for loop closure
<!--stackedit_data:
eyJoaXN0b3J5IjpbLTg4MjYxMzUwNl19
-->