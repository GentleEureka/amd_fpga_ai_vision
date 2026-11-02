---
name: cam1-vision
description: Query the live CAM1 FPGA vision stream, current scene, persisted events, and supported FPGA image algorithms through the Cam1 Vision MCP server.
---

# Cam1 Vision

Use the Cam1 Vision MCP tools to answer questions about the live camera and its recorded scene events.

## Current scene and live image

- Use `get_current_scene` for the latest semantic scene, visible objects, states, and freshness.
- Use `get_live_camera_frame` only when the user needs to inspect the latest image.
- Use `get_vision_status` or `get_continuous_perception_status` to explain stream and model readiness.
- Treat a stale or unavailable frame as unavailable; do not invent scene details.

## Past actions

- For questions about earlier actions, use `search_scene_memory` or `get_recent_scene_events`.
- Report confirmed events separately from pending clues.
- Do not infer past actions from a newly captured image.

## Image algorithms

- Call `list_vision_algorithms` to check supported modes and the FPGA mode currently read back from the stream.
- The stream is 1920x1080 JPEG from the OV5640. The FPGA relays mode commands to the sensor over SCCB and reports the applied mode in later JPEG frame metadata.
- When asked to change the sensor image mode, call `select_fpga_algorithm` with `color`, `gray`, `binary` (OV5640 black-and-white effect), or `invert` (negative effect).
- Report the returned hardware verification status; a command being sent is not proof that the sensor applied it.
