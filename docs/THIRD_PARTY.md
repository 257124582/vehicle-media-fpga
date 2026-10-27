# 依赖与代码来源

本工程以安路赛事参考例程`lab_ex5_i2s`及HX4S20C开发板资料为基础。厂商代码保留原始版权和来源注释，文件级记录见`vendor_manifest.json`。

- HDMI发送器加密核心、PHY及串行器来自原厂参考例程；加密载荷未改动。
- SDRAM控制器来自原厂参考设计。`global_def.v`调整为40 MHz存储域参数，`vendor/reference/global_def_125MHz.v`保留参考宏。外围读数据对齐和刷新保护在工程中实现。
- `rtl/media_sys_pll.v`及`rtl/media_video_pll.v`由厂商PLL配置适配，原始文件保存在`vendor/IP/`。文件中的IP Generator说明属于正常工具来源记录。
- `vendor/simulation/IS42s32200.v`来自APUG011参考资料，具体条目和校验值见相邻`source.json`。
- `vendor/SD/`为原厂SD参考模块，保留作来源对照，当前综合工程采用`rtl/sd_spi_reader.v`。
- FAT32/BMP解析、缩放、帧缓存管理、图像处理、交互控制、车载场景、菜单、串口和PCM波形位于`rtl/`。字模常量由`tools/generate_vehicle_osd.py`生成，现有RTL可直接综合，无需重新生成字模。
- 字模生成脚本使用Windows系统黑体字体；包内不分发系统字体文件。NumPy与Pillow由使用者单独安装，不随包分发。

厂商IP的使用范围遵循其原始授权及赛事资料规定。本说明不改变第三方授权，也不将厂商模块标为项目原创。
