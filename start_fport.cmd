@echo off
echo 正在设置端口转发...
hdc -t 127.0.0.1:5557 fport tcp:8888 tcp:8888
echo 端口转发设置完成！
pause

/device/1/telemetry
{"device_type":"temp_humi_sensor","temperature":25.8,"humidity":55.5,"lux":420.0}