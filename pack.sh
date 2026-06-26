#!/bin/bash

# 打包脚本 - 创建发布包

VERSION="1.0.0"
PACKAGE_NAME="traffic-limiter-v${VERSION}"
BUILD_DIR="build"

echo "=========================================="
echo "      流量限制器 - 打包脚本"
echo "=========================================="
echo ""

# 清理旧的构建
rm -rf $BUILD_DIR
rm -f ${PACKAGE_NAME}.tar.gz

# 创建构建目录
mkdir -p $BUILD_DIR/$PACKAGE_NAME

# 复制文件
echo "正在复制文件..."
cp -r config $BUILD_DIR/$PACKAGE_NAME/
cp -r scripts $BUILD_DIR/$PACKAGE_NAME/
cp -r systemd $BUILD_DIR/$PACKAGE_NAME/
cp -r logrotate $BUILD_DIR/$PACKAGE_NAME/
cp -r docs $BUILD_DIR/$PACKAGE_NAME/
cp install.sh $BUILD_DIR/$PACKAGE_NAME/
cp uninstall.sh $BUILD_DIR/$PACKAGE_NAME/
cp README.md $BUILD_DIR/$PACKAGE_NAME/ 2>/dev/null || cp docs/README.md $BUILD_DIR/$PACKAGE_NAME/README.md

# 设置权限
echo "正在设置权限..."
chmod +x $BUILD_DIR/$PACKAGE_NAME/install.sh
chmod +x $BUILD_DIR/$PACKAGE_NAME/uninstall.sh
chmod +x $BUILD_DIR/$PACKAGE_NAME/scripts/*.sh
chmod +x $BUILD_DIR/$PACKAGE_NAME/scripts/traffic_ctl.sh

# 创建压缩包
echo "正在创建压缩包..."
cd $BUILD_DIR
tar -czf ${PACKAGE_NAME}.tar.gz $PACKAGE_NAME
cd ..

# 移动到项目根目录
mv $BUILD_DIR/${PACKAGE_NAME}.tar.gz ./

echo ""
echo "=========================================="
echo "      打包完成！"
echo "=========================================="
echo ""
echo "发布包: ${PACKAGE_NAME}.tar.gz"
echo "大小: $(du -h ${PACKAGE_NAME}.tar.gz | cut -f1)"
echo ""
echo "安装方法:"
echo "  tar -zxvf ${PACKAGE_NAME}.tar.gz"
echo "  cd ${PACKAGE_NAME}"
echo "  ./install.sh"
echo ""
