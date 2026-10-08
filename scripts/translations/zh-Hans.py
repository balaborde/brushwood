# 简体中文 (zh-Hans) UI strings: one "English source string|translation" per line. The English side is exactly
# as written in the Swift source (escapes included); run scripts/gen_strings.py after editing.
T = dict(line.split('|', 1) for line in r"""
%@ copy|%@ 副本
%d x %d Region|%d x %d 区域
10 Percent|10%
20 Percent|20%
24-bit|24 位
25 Percent|25%
32-bit|32 位
4 Point Star|四角星
5 Percent|5%
5 Point Star|五角星
50 Percent|50%
6 Point Star|六角星
75 Percent|75%
8 Point Star|八角星
90 Percent|90%
A free, open-source image editor for macOS, modeled on the workflow of Paint.NET.\n\nLicensed under the MIT License.\nNot affiliated with or endorsed by dotPDN LLC. Paint.NET is a trademark of its respective owner.|一款免费、开源的 macOS 图像编辑器，以 Paint.NET 的工作方式为蓝本。\n\n基于 MIT 许可证发布。\n与 dotPDN LLC 无关联，也未获其认可。Paint.NET 是其所有者的商标。
About Brushwood|关于 Brushwood
Actual Size|实际大小
Add (union)|添加（并集）
Add New Layer|添加新图层
Add Noise|添加杂色
Additive|相加
Adjustments|调整
After click|单击后
After click:|单击后：
Algorithm|算法
Aliased|锯齿
Amount|数量
Anchor|锚点
Angle|角度
Antialias selection edges when clipping|裁剪时对选区边缘消除锯齿
Antialiased|已消除锯齿
Antialiasing|消除锯齿
Antialiasing disabled|消除锯齿已关闭
Antialiasing enabled|消除锯齿已打开
Appearance|外观
Arrow|箭头
Arrows|箭头
Artistic|艺术
Auto|自动
Auto-Level|自动色阶
Auto-Level, Black and White, Brightness / Contrast, Curves|自动色阶、黑白、亮度 / 对比度、曲线
Auto-detect|自动检测
Background|背景
Backward Diagonal|反向对角线
Basic|基本
Best Quality|最佳质量
Bicubic|双三次
Bilinear|双线性
Bit Depth|位深度
Black and White|黑白
Blend|混合
Blend mode|混合模式
Blend modes not supported by Paint.NET|Paint.NET 不支持的混合模式
Blending|混合
Blending:|混合：
Blue|蓝
Blur radius|模糊半径
Blurs|模糊
Bokeh Blur|散景模糊
Bold|粗体
Brightness|亮度
Brightness / Contrast|亮度 / 对比度
Brush size|画笔大小
Brush width (mouse wheel, [ and ] also change it)|画笔宽度（也可用鼠标滚轮、[ 和 ] 更改）
Brush width:|画笔宽度：
Brushwood Help|Brushwood 帮助
Brushwood is a free image editor for macOS whose workflow follows Paint.NET: one main window with image tabs, floating Tools, History, Layers and Colors windows, layers with blend modes, unlimited history, and a large set of adjustments and effects with live preview.|Brushwood 是一款免费的 macOS 图像编辑器，其工作方式与 Paint.NET 一致：一个带图像标签页的主窗口，浮动的“工具”“历史记录”“图层”“颜色”窗口，支持混合模式的图层，无限历史记录，以及大量带实时预览的调整和效果。
Bulge|凸起
By absolute size|按绝对大小
By percentage:|按百分比：
Callouts|标注
Cancel|取消
Canvas Size|画布大小
Canvas Size…|画布大小…
Cell Size|单元格大小
Cell size|单元格大小
Center|居中
Centered|居中
Centimeters|厘米
Chebyshev|切比雪夫
Chevron|V 形
Clamp|钳制
Clear Menu|清除菜单
Click and drag to draw a gradient from the primary to the secondary color. Right mouse button reverses the colors.|单击并拖移以绘制从主要颜色到次要颜色的渐变。使用右键会交换颜色。
Click and drag to draw a line. Then drag the handles to bend it into a curve. Press Enter to finish.|单击并拖移以绘制直线，然后拖移控制点将其弯曲成曲线。按 Return 键完成。
Click and drag to draw a rectangular selection. Hold Shift to constrain to a square. ⌘ adds, ⌥ subtracts, right-click inverts.|单击并拖移以绘制矩形选区。按住 Shift 键可限制为正方形。⌘ 添加，⌥ 减去，右键反转。
Click and drag to draw a shape. Drag the handles to adjust it. Press Enter to finish.|单击并拖移以绘制形状。拖移控制点进行调整。按 Return 键完成。
Click and drag to draw an elliptical selection. Hold Shift to constrain to a circle. ⌘ adds, ⌥ subtracts, right-click inverts.|单击并拖移以绘制椭圆选区。按住 Shift 键可限制为圆形。⌘ 添加，⌥ 减去，右键反转。
Click and drag to draw the outline of a selection area. ⌘ adds, ⌥ subtracts, right-click inverts.|单击并拖移以绘制选区的轮廓。⌘ 添加，⌥ 减去，右键反转。
Click and drag to erase a portion of the image.|单击并拖移以擦除图像的一部分。
Click and drag to navigate the image.|单击并拖移以浏览图像。
Click to add a point, drag to move it, right-click to remove it.|单击以添加点，拖移以移动点，右键单击以删除点。
Click to select a region of similar color. ⌘ adds, ⌥ subtracts, right-click inverts. Shift-click for global selection.|单击以选择颜色相近的区域。⌘ 添加，⌥ 减去，右键反转。按住 Shift 键单击进行全局选择。
Clipping:|裁剪：
Clone Stamp|仿制图章
Clone source set at %d, %d|仿制源已设为 %d, %d
Close|关闭
Close Others|关闭其他
Cloud|云朵
Clouds|云彩
Coarseness|颗粒度
Color|颜色
Color Burn|颜色加深
Color Dodge|颜色减淡
Color Mode|颜色模式
Color Picker|颜色选择器
Color Saturation|色彩饱和度
Color count|颜色数
Color range|颜色范围
Coloring|着色
Colors|颜色
Colors (F8)|颜色 (F8)
Commands|命令
Conical|圆锥
Contiguous|连续
Contrast|对比度
Copy|拷贝
Copy (⌘C)|拷贝 (⌘C)
Copy / paste the selection outline|拷贝 / 粘贴选区轮廓
Copy Merged|合并拷贝
Copy Selection|拷贝选区
Could not open \"%@\"|无法打开“%@”
Could not save \"%@\"|无法存储“%@”
Coverage|覆盖率
Crop to Selection|裁剪到选区
Crop to Selection (⇧⌘X)|裁剪到选区 (⇧⌘X)
Cross|十字
Crystalize|晶格化
Curvature|曲率
Curve|曲线
Curves|曲线
Cut|剪切
Cut (⌘X)|剪切 (⌘X)
Cut, Copy, Paste|剪切、拷贝、粘贴
Cycle tools sharing a letter in reverse (⇧S = Magic Wand)|反向循环切换共用同一字母的工具（⇧S = 魔棒）
Cylinder|圆柱
Dark|深色
Dark Horizontal|深色横线
Dark Vertical|深色竖线
Darken|变暗
Dash|划线
Dash Dot|点划线
Dash Dot Dot|双点划线
Dash style|虚线样式
Dash:|虚线：
Dashed Horizontal|横虚线
Dashed Vertical|竖虚线
Decrease / increase brush width (Shift: ×10)|减小 / 增大画笔宽度（Shift：×10）
Delete Layer|删除图层
Dents|凹痕
Deselect|取消选择
Deselect (⌘D)|取消选择 (⌘D)
Diagonal Brick|斜砖
Diagonal Cross|斜十字
Diamond|菱形
Difference|差值
Dilate|膨胀
Distance|距离
Distance metric|距离度量
Distort|扭曲
Dithering|仿色
Divot|草皮
Do not switch tool|不切换工具
Don't Save|不存储
Dot|点
Dotted Diamond|点线菱形
Dotted Grid|点线网格
Double Arrow|双箭头
Down Arrow|下箭头
Drag the selection outline to move it. Drag the handles to scale. Drag with the right mouse button to rotate.|拖移选区轮廓可移动，拖移控制点可缩放，按住右键拖移可旋转。
Drag the selection to move it. Drag the handles to scale. Drag with the right mouse button to rotate. Hold ⌘ while dragging to leave a copy behind.|拖移选区可移动，拖移控制点可缩放，按住右键拖移可旋转。拖移时按住 ⌘ 键可留下副本。
Draw Filled Shape|填充形状
Draw Filled Shape With Outline|带轮廓的填充形状
Draw Shape Outline|形状轮廓
Drop Shadow|投影
Duplicate Layer|复制图层
Edge Behavior|边缘行为
Edge Detect|边缘检测
Edit|编辑
Editable shapes|可编辑的形状
Effects|效果
Ellipse|椭圆
Ellipse Callout|椭圆标注
Ellipse Select|椭圆选择
Emboss|浮雕
End cap|末端样式
End:|末端：
Enter Full Screen|进入全屏幕
Erase Selection|抹除选区
Eraser|橡皮擦
Erode|腐蚀
Euclidean|欧几里得
Expand canvas|扩大画布
Explosion|爆炸
Exposure|曝光
Factor|系数
Fast-forward to the end|快进到末尾
Feather|羽化
File|文件
File size: %@|文件大小：%@
Files|文件
Fill Selection|填充选区
Fill style|填充样式
Fill:|填充：
Filled Arrow|实心箭头
Finish|完成
Finish (Return)|完成 (Return)
Finish / cancel the current edit (⏎ again deselects)|完成 / 取消当前编辑（再次按 ⏎ 取消选择）
Fixed Ratio|固定比例
Fixed Size|固定大小
Flat|平头
Flatten|拼合
Flatten image|拼合图像
Flip Horizontal|水平翻转
Flip Layer Horizontal|水平翻转图层
Flip Layer Vertical|垂直翻转图层
Flip Vertical|垂直翻转
Flood mode:|填充模式：
Font:|字体：
Format:|格式：
Forward Diagonal|正向对角线
Fractal Sum|分形和
Fragment Blur|碎片模糊
Fragments|碎片数
Frosted Glass|磨砂玻璃
Gamma|伽马
Gamma Boost|伽马增强
Gaussian Blur|高斯模糊
General|通用
Global|全局
Glow|发光
Go to Bottom Layer|转到最底层图层
Go to Layer Above|转到上一图层
Go to Layer Below|转到下一图层
Go to Top Layer|转到最顶层图层
Go to the layer above / below|转到上 / 下一图层
Gradient|渐变
Gradient:|渐变：
Green|绿
Guide|指南
Hard Light|强光
Hardness:|硬度：
Heart|心形
Height|高度
Height:|高度：
Help|帮助
Hex:|十六进制：
Hexagon|六边形
Hide Brushwood|隐藏 Brushwood
Hide Others|隐藏其他
Highlight boost|高光增强
Highlights|高光
Highlights / Shadows|高光 / 阴影
Hint: For best results, first use the selection tools to select each eye.|提示：为获得最佳效果，请先用选择工具选中每只眼睛。
History|历史记录
History (F6)|历史记录 (F6)
Hold to pan|按住以平移
Horizontal|水平
Horizontal Brick|横砖
Hue|色相
Hue / Saturation|色相 / 饱和度
Hue / Saturation, Invert Alpha, Invert Colors, Levels|色相 / 饱和度、反相 Alpha、反相颜色、色阶
If you don't save, your changes will be lost.|如果不存储，你的更改将会丢失。
Image|图像
Image larger than canvas|图像大于画布
Import From File|从文件导入
Import From File…|从文件导入…
Inches|英寸
Ink Sketch|墨水素描
Ink outline|墨水轮廓
Input black|输入黑场
Input white|输入白场
Intensity|强度
Intersect|交集
Invert (xor)|反转（异或）
Invert Alpha|反相 Alpha
Invert Colors|反相颜色
Invert Selection|反选
Italic|斜体
Julia Fractal|朱利亚分形
Keep canvas size|保持画布大小
Keyboard Shortcuts|键盘快捷键
Lanczos 3|Lanczos 3
Language|语言
Large Checker Board|大棋盘格
Large Grid|大网格
Lasso Select|套索选择
Layer|图层
Layer %d|图层 %d
Layer Hidden|图层已隐藏
Layer Properties|图层属性
Layer Properties…|图层属性…
Layer Shown|图层已显示
Layered images are saved as Paint.NET files (.pdn) or in the OpenRaster format (.ora), which Krita, GIMP and MyPaint also open. PNG, JPEG, BMP, GIF, TIFF, TGA, DDS, HEIC, AVIF and ICO can be saved; WebP, JPEG XL and PSD can be opened.|带图层的图像会存储为 Paint.NET 文件 (.pdn) 或 OpenRaster 格式 (.ora)，后者也可以用 Krita、GIMP 和 MyPaint 打开。可以存储为 PNG、JPEG、BMP、GIF、TIFF、TGA、DDS、HEIC、AVIF 和 ICO，并可以打开 WebP、JPEG XL 和 PSD。
Layers|图层
Layers (F7)|图层 (F7)
Left|左
Left Arrow|左箭头
Left click to draw freehand one-pixel wide lines with the primary color, right click to use the secondary color.|左键单击以主要颜色徒手绘制一像素宽的线条，右键单击则使用次要颜色。
Left click to draw with the primary color, right click to draw with the secondary color.|左键单击以主要颜色绘画，右键单击以次要颜色绘画。
Left click to fill a region with the primary color, right click to fill with the secondary color.|左键单击以主要颜色填充区域，右键单击以次要颜色填充。
Left click to place the cursor, then type the desired text. The text color is the primary color.|单击以放置光标，然后输入文本。文本颜色为主要颜色。
Left click to replace the secondary color with the primary color.|左键单击以主要颜色替换次要颜色。
Left click to set the primary color. Right click to set the secondary color.|左键单击设置主要颜色，右键单击设置次要颜色。
Left click to zoom in. Right click to zoom out. Click and drag to zoom in on a rectangle.|左键单击放大，右键单击缩小。单击并拖移可放大到矩形区域。
Left-click a swatch to set the primary color, right-click for the secondary color. Shift-click stores the current color.|左键单击色板设置主要颜色，右键单击设置次要颜色。按住 Shift 键单击可存储当前颜色。
Less «|更少 «
Levels|色阶
Light|浅色
Light Horizontal|浅色横线
Light Vertical|浅色竖线
Lighten|变亮
Lighting|光照
Lightness|明度
Lightning|闪电
Line|直线
Line / Curve|直线 / 曲线
Linear|线性
Linear (Diamond)|线性（菱形）
Linear (Reflected)|线性（反射）
Linked|关联
Luminosity|明度
Magic Wand|魔棒
Maintain aspect ratio|保持纵横比
Mandelbrot Fractal|曼德博分形
Manhattan|曼哈顿
Maximum scatter radius|最大散射半径
Median Blur|中值模糊
Median Cut|中位切分
Merge Layer Down|向下合并图层
Minimize|最小化
Minimum scatter radius|最小散射半径
Mode|模式
Mode:|模式：
Moon|月亮
More »|更多 »
Morphology|形态学
Motion Blur|动感模糊
Move Layer Down|下移图层
Move Layer Up|上移图层
Move Layer to Bottom|将图层移到底部
Move Layer to Top|将图层移到顶部
Move Selected Pixels|移动所选像素
Move Selection|移动选区
Multiply|正片叠底
Name:|名称：
Nearest Neighbor|邻近
Negation|求反
New|新建
New (⌘N)|新建 (⌘N)
New Image|新建图像
New size: %@|新大小：%@
New size: %d × %d (%@)|新大小：%d × %d（%@）
New…|新建…
Next Image|下一个图像
Next image|下一个图像
No Repeat|不重复
Noise|杂色
Normal|正常
Number of cells|单元格数量
OK|好
Object|对象
Octagon|八边形
Octaves|八度
Octree|八叉树
Offset|偏移
Oil Painting|油画
Opacity|不透明度
Opacity:|不透明度：
Open|打开
Open (⌘O)|打开 (⌘O)
Open Image|打开图像
Open Palette…|打开调色板…
Open Recent|打开最近使用
Open…|打开…
Original|原始
Outline|轮廓
Outline Object|对象轮廓
Outlined Diamond|空心菱形
Output black|输出黑场
Output white|输出白场
Overlay|叠加
Overwrite|覆盖
Paint Bucket|油漆桶
Paintbrush|画笔
Palette|调色板
Pan|抓手
Parallelogram|平行四边形
Paste|粘贴
Paste (⌘V)|粘贴 (⌘V)
Paste Into New Image|粘贴到新图像
Paste Into New Layer|粘贴到新图层
Paste Selection|粘贴选区
Paste Selection (Replace)|粘贴选区（替换）
Pencil|铅笔
Pencil Sketch|铅笔素描
Pencil tip size|铅笔笔尖大小
Pentagon|五边形
Percentile|百分位数
Period|周期
Photo|照片
Pixel Grid|像素网格
Pixel Grid (⌘')|像素网格 (⌘')
Pixel size|像素大小
Pixelate|像素化
Pixels|像素
Plaid|格子呢
Plus|加号
Polar Inversion|极坐标反转
Polygons|多边形
Posterize|色调分离
Posterize, Sepia|色调分离、棕褐色
Preserve transparency|保留透明度
Previous Image|上一个图像
Primary|主要
Print (⌘P)|打印 (⌘P)
Print size|打印尺寸
Print…|打印…
Quality|品质
Quality:|品质：
Quantize|量化
Quit Brushwood|退出 Brushwood
RGB|RGB
RLE compression|RLE 压缩
Radial|径向
Radial Blur|径向模糊
Radius|半径
Radius:|半径：
Random Noise|随机杂色
Random positions and colors|随机位置和颜色
Randomize|随机
Recolor|重新着色
Rectangle|矩形
Rectangle Callout|矩形标注
Rectangle Select|矩形选择
Red|红
Red Eye Removal|消除红眼
Redo|重做
Redo %@|重做“%@”
Redo (⇧⌘Z)|重做 (⇧⌘Z)
Reduce Noise|减少杂色
Reflect|反射
Refraction|折射
Relief|浮凸
Render|渲染
Repeat|重复
Repeat %@|重复“%@”
Repeat last effect|重复上一个效果
Replace|替换
Resampling|重新采样
Resampling:|重新采样：
Reseed|重新生成种子
Reset|重置
Reset Colors|重置颜色
Reset Palette to Default|将调色板恢复为默认
Reset Window Positions|重置窗口位置
Reset to Default|恢复默认值
Resize|调整大小
Resize Image|调整图像大小
Resize…|调整大小…
Resolution:|分辨率：
Restart Brushwood to use the new language.|重新启动 Brushwood 以使用新语言。
Restart Now|立即重新启动
Rewind to the beginning|倒回到开头
Right|右
Right Arrow|右箭头
Right Triangle|直角三角形
Rotate / Zoom|旋转 / 缩放
Rotate / Zoom…|旋转 / 缩放…
Rotate 180°|旋转 180°
Rotate 90° CW / 90° CCW / 180°|顺时针 90° / 逆时针 90° / 180° 旋转
Rotate 90° Clockwise|顺时针旋转 90°
Rotate 90° Counter-clockwise|逆时针旋转 90°
Rotate Layer 180°|旋转图层 180°
Rotation|旋转
Roughness|粗糙度
Rounded|圆角
Rounded Rectangle|圆角矩形
Rounded Rectangle Callout|圆角矩形标注
Rulers|标尺
Rulers (⌥⌘R)|标尺 (⌥⌘R)
Sample size|取样大小
Sampling|取样
Sampling:|取样：
Saturation|饱和度
Saturation percentage|饱和度百分比
Save|存储
Save (⌘S)|存储 (⌘S)
Save All|全部存储
Save Anyway|仍然存储
Save As|存储为
Save As…|存储为…
Save Configuration — %@|存储选项 — %@
Save Palette As…|将调色板存储为…
Save changes to \"%@\"?|要存储对“%@”的更改吗？
Sawtooth Repeat|锯齿波重复
Scale|比例
Screen|滤色
Secondary|次要
Secondary color|次要颜色
Seed|种子
Select All|全选
Select All / Deselect|全选 / 取消选择
Selection|选区
Selection clipping|选区裁剪
Selection drawing mode|选区绘制模式
Selection mode:|选择模式：
Selection tools combine with the existing selection: ⌘ adds (union), ⌥ subtracts, right-click inverts (xor) and ⌥+right-click intersects. The mode can also be chosen in the tool bar.|选择工具会与现有选区组合：⌘ 添加（并集），⌥ 减去，右键反转（异或），⌥+右键取交集。也可以在工具栏中选择模式。
Selection: %d × %d|选区：%d × %d
Selections|选区
Sepia|棕褐色
Services|服务
Settings|设置
Settings (⌘,)|设置 (⌘,)
Settings…|设置…
Shadow only|仅阴影
Shadows|阴影
Shape:|形状：
Shapes|形状
Shapes, lines, gradients, text and paint bucket fills stay editable after you draw them: drag their handles or change options in the tool bar. Press Return or switch tools to finish, Escape or ⌘Z to cancel.|形状、直线、渐变、文本和油漆桶填充在绘制后仍可编辑：拖移控制点或在工具栏中更改选项。按 Return 键或切换工具以完成，按 Esc 键或 ⌘Z 取消。
Sharpen|锐化
Shingle|瓦片
Show All|全部显示
Show in Finder|在访达中显示
Show points|显示点
Single Pixel|单个像素
Size|大小
Sketch Blur|素描模糊
Small Checker Board|小棋盘格
Small Grid|小网格
Smoothness|平滑度
Soft Light|柔光
Soften Portrait|柔化人像
Softness|柔和度
Solid|实线
Solid Color|纯色
Solid Diamond|实心菱形
Space|空格键
Sphere|球面
Spiral (Clockwise)|螺旋（顺时针）
Spiral (Counter-clockwise)|螺旋（逆时针）
Square Blur|方块模糊
Stars|星形
Start cap|起点样式
Start:|起点：
Straighten|拉直
Strength|力度
Strikethrough|删除线
Stylize|风格化
Subtract|减去
Supersampling|超采样
Surface Blur|表面模糊
Swap Colors|交换颜色
Swap primary and secondary colors|交换主要颜色和次要颜色
Switch to Pencil tool|切换到铅笔工具
Switch to previous tool|切换到上一个工具
Symbols|符号
Temperature|色温
Temperature and Tint|色温和色调
Tension|张力
Text|文本
The image being pasted is larger than the canvas size. What would you like to do?|粘贴的图像大于画布。你想怎么做？
These blend modes will be saved as Normal in the .pdn file: %@. Save as OpenRaster (.ora) to keep them.|这些混合模式在 .pdn 文件中将存储为“正常”：%@。若要保留它们，请存储为 OpenRaster (.ora)。
Thickness|粗细
This file format does not support layers. The saved file will contain a flattened copy of the image; your layers are kept in Brushwood.|此文件格式不支持图层。存储的文件将包含图像的拼合副本；你的图层仍保留在 Brushwood 中。
This is not a Paint.NET (.pdn) file.|这不是 Paint.NET (.pdn) 文件。
Threshold|阈值
Tile Reflection|拼贴反射
Tile Size|拼贴大小
Tiling|拼贴
Tint|色调
Toggle Layer Visibility|显示/隐藏图层
Tolerance|容差
Tolerance:|容差：
Tool:|工具：
Tools|工具
Tools (F5)|工具 (F5)
Tools, History, Layers, Colors windows|“工具”“历史记录”“图层”“颜色”窗口
Transfer Map:|传递映射：
Transparency Mode|透明模式
Transparent|透明
Trapezoid|梯形
Trellis|格架
Triangle|三角形
Triangle Repeat|三角波重复
Turbulence|湍流
Twist|扭转
Underline|下划线
Undo|撤销
Undo %@|撤销“%@”
Undo (⌘Z)|撤销 (⌘Z)
Units|单位
Untitled|未命名
Up Arrow|上箭头
Use System Setting|使用系统设置
Value|值
Vertical|垂直
View|显示
Vignette|晕影
Visible|可见
Voronoi Diagram|沃罗诺伊图
Warmth|暖度
Wave|波浪
Weave|编织
Welcome to Brushwood|欢迎使用 Brushwood
White|白色
Width|宽度
Width:|宽度：
Window|窗口
Wrap|环绕
Xor|异或
Zig Zag|之字形
Zoom|缩放
Zoom Amount|缩放量
Zoom Blur|缩放模糊
Zoom In|放大
Zoom In / Out|放大 / 缩小
Zoom Out|缩小
Zoom to Selection|缩放到选区
Zoom to Window|缩放到窗口
centimeters|厘米
cm|cm
in|in
inches|英寸
letter|字母
pixels|像素
pixels/inch|像素/英寸
px|px
⌘-click to set the clone origin first.|请先按住 ⌘ 键单击以设置仿制源。
⌘-click to set the origin, then click and drag to paint with the cloned pixels.|按住 ⌘ 键单击以设置源点，然后单击并拖移，用仿制的像素绘画。
""".strip().splitlines())
