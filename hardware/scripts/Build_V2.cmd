@echo off
setlocal
cd /d "%~dp0"

set "VIVADO_BAT="
for %%V in (
  "C:\Xilinx\Vivado\2023.1\bin\vivado.bat"
  "D:\Xilinx\Vivado\2023.1\bin\vivado.bat"
  "C:\AMD\Vivado\2023.1\bin\vivado.bat"
  "D:\AMD\Vivado\2023.1\bin\vivado.bat"
) do if not defined VIVADO_BAT if exist "%%~V" set "VIVADO_BAT=%%~V"
if not defined VIVADO_BAT for %%V in (vivado.bat) do set "VIVADO_BAT=%%~$PATH:V"

if not defined VIVADO_BAT (
  echo Vivado 2023.1 was not found. Install it or add its bin folder to PATH.
  pause
  exit /b 1
)

call "%VIVADO_BAT%" -mode batch -nolog -nojournal -source ".\scripts\build_bitstream.tcl"
if errorlevel 1 exit /b 1
echo Build complete: %CD%\output\generated\amd_fpga_continuous_vision_v2.bit
