# 车载多媒体乘客信息终端

平台：HX4S20C，EG4S20BG256；工具：TD 6.2.168116。HDMI_B输出640×480视频与48 kHz合成PCM音频。

## 文件结构

- `rtl/`：完整设计RTL，顶层为`vehicle_media_top`。
- `vendor/`：厂商HDMI、SDRAM、PLL及仿真模型，来源见`docs/THIRD_PARTY.md`。
- `constraints/`：引脚和时序约束；`project/vehicle_media.al`为TD工程。
- `tests/`、`sim/`：全部25个测试平台文件及接口模型。
- `tools/`：构建、仿真、素材参考、字模生成、串口控制和状态解析工具。
- `assets/tf_card_extended/`：上板使用的四幅混合尺寸BMP；`assets/tf_card/`为固定尺寸回归素材。
- `assets/reference*/`：整数参考结果和像素数据；大型磁盘镜像由回归脚本生成。
- `build/td/`：已经通过构建的bit、资源及时序摘要、源码校验记录。
- `docs/操作说明.md`：常用按键、串口和演示步骤。

## 编译和下载

1. 解压到可写目录，建议使用英文路径。安装TD 6.2.168116与Python 3.10或以上版本。
2. Python依赖安装命令：`python -m pip install -r requirements.txt`。普通编译不依赖这些图像库，素材与参考计算需要它们。
3. 如工具不在PATH中，设置`TD_EXE`为`td_commands_prompt.exe`完整路径；可用`PYTHON_EXE`指定Python可执行文件。
4. `open_project.cmd`刷新当前工程位置并打开TD工程。重新编译使用`rebuild.cmd`，每次显式启用`gate eram_init on`，随后校验3200个字模存储字。
5. bit位于`build/td/vehicle_media.bit`。连接USB-JTAG后执行`download_sram.cmd`；该脚本核对源文件校验和及目标器件，只写SRAM，不写Flash。下载不作为解压或编译的自动步骤。
6. TF卡使用FAT32，将`assets/tf_card_extended/`中的四个BMP文件复制到根目录。HDMI_B接显示设备，声音输出还需扬声器。

## 仿真

已使用ModelSim DE-64 10.6c验证。将`MODELSIM_BIN`设为含`vsim.exe`、`vlog.exe`和`vlib.exe`的目录，执行`run_regression.cmd`。完整回归包含文件系统、缩放、图像处理、控制、音频、车载图层与顶层联合验证，运行时间取决于计算机性能。输出位于`build/sim/`，无需连接板卡。

仅运行车载状态机与按键专项可执行`python tools/run_v3_extra.py`。原始图像链路测试有图层旁路，顶层车载测试有媒体状态强制，不能把这些仿真当作全部物理接口的实板验收。

## 运行范围

当前设计支持FAT32根目录前四幅有效24位未压缩BMP，源尺寸宽1～1024、高1～768，单文件不超过4 MiB；先装载后显示。站点由按键或串口控制；音频为合成提示音；昼夜参数在复位后恢复默认。

留档构建的建立/保持余量为1.658 ns/0.023 ns。2026年10月16日SRAM功能检查确认四图装载、图像文字、声音及按键菜单；所记录检查点缺数、读超时与HDMI输入违例为0。未完成30分钟稳定性、Flash固化与冷启动验收。代码包本次整理不改变RTL或约束，不增加新的实板验收结论。

`CHECKSUMS.sha256`列出交付文件校验值。原厂版权、来源标记与加密IP保持原样。
