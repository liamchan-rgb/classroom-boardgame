from pathlib import Path
import json,hashlib,zipfile,html
R=Path(__file__).resolve().parents[1]
BRIEF=R/'sources/reference_inputs'
def write(name,d):
 p=R/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n' if not isinstance(d,str) else d)
t=json.loads((BRIEF/'design/design-tokens_v1.json').read_text());t.update(status='proposed-round1-not-approved',deliveryVersion='2026-10-12-round1')
t['colors'].update(accent='#995207',onAccent='#FFFFFF',onDanger='#FFFFFF',teamBlue='#315E9C',teamOrange='#995207',teamViolet='#6650A4',border='#CDD8D0',disabledSurface='#EDF0EA')
t['materials']={'largePanels':{'native':'SwiftUI Material.regular','preferredAppearance':'light','clipRadiusPt':16,'backdrop':'低对比度非语义装饰，避免高饱和穿透文字','textProtection':'数值区域以浅色底衬控制对比度','preview':'SVG白色83–96%渐变是静态毛玻璃近似；真实模糊、振动和系统降低透明度由原生环境验证'},'smallControls':{'primary':'solid primary + white label','secondary':'iPadOS27 system liquid glass when supported, otherwise solid surface','reward':'solid warm tint; accent border and explicit checkmark','reduceTransparency':'solid surface'}}
t['styleVariants']={'a':{'label':'晨光森林','background':'#F5F1E8','land':'#D4DFCA','tint':'#E4EDD9'},'b':{'label':'晴空学园','background':'#F5F1E8','land':'#D7E8DF','tint':'#DEEFF3'}}
t['publicTypographyUnits'].update(name=28,resource=26,queue=24,focus=44)
t['teacherTypographyPt'].update(name=17,body=18,resource=20)
t['layoutReferences']={'teacher':{'width':1366,'height':1024,'margin':24,'columnGap':16,'leftWidth':268,'centerWidth':666,'rightWidth':352},'public16x9':{'width':1920,'height':1080,'safeInsets':[54,96,54,96],'cardWidth':420,'cardHeight':124,'cardYs':[770,902],'cardGap':16},'public4x3':{'width':1440,'height':1080,'safeInsets':[54,72,54,72],'cardWidth':312,'cardHeight':156,'cardYs':[682,854],'cardGap':16}}
t['teamMarkers']={'blue':'circle','orange':'diamond','violet':'triangle','notes':'名称及形状共同标识，可新增队伍，不限定三队'}
t['font']['preview']='Noto Sans CJK SC installed in design environment; not a runtime requirement'
write('design-tokens.json',t)
m=json.loads((BRIEF/'design/asset-manifest_v1.json').read_text());m.update(status='round1-style-samples-and-ui-icons',deliveryVersion='2026-10-12-round1',preferredStyle=None)
m['notes']+=['A/B是同一ID的审美备选，不同时映射为两个职业。尚未确认方向，开发接入须显式选择style。','其余3职业及5怪物的最终头像仍planned，不将中性占位符误记为已完成。','样稿的生成原图及1024标准导出画布保留在sources；导出不修改造型。']
for a in m['assets']:
 a['styleVersion']='round1';a['license']='待制作' if a['status']=='planned' else None
 if a['entityID'] in ['adventurer','slime'] and a['entityType'] in ['classes','monsters']:
  id=a['assetName'];a['status']='style-sample-not-final';a['file']='assets/style_a/'+id+'.png';a['source']='本对话 image_gen 原创生成，导出为独立透明PNG';a['license']='适用OpenAI服务条款；未引用第三方角色素材，未声明独占权';a['variants']=[]
  for st in ['a','b']:
   fn='assets/style_'+st+'/'+id+'.png';a['variants'].append({'style':st,'file':fn,'source':'sources/original_'+st+'_'+id.replace('_portrait','')+'.png','exportSource':'sources/export_'+st+'_'+id.replace('_portrait','')+'.svg','status':'style-sample-not-final','widthPx':1024,'heightPx':1024,'transparent':True,'colorSpace':'sRGB','sha256':hashlib.sha256((R/fn).read_bytes()).hexdigest()})
for key,label in [('health','生命'),('shield','护盾'),('action','行动点'),('coin','金币'),('score','积分'),('downed','倒地')]:
 fn='assets/icons/icon_'+key+'.png';m['assets'].append(dict(entityType='uiResource',entityID=key,label=label,assetName='icon_'+key,file=fn,vectorSource='assets/icons/icon_'+key+'.svg',widthPx=256,heightPx=256,transparent=True,colorSpace='sRGB',batch='A',status='delivered-original-vector',styleVersion='round1',source='本交付原创SVG几何绘制',license='本项目可本地使用与修改；无外部素材',sha256=hashlib.sha256((R/fn).read_bytes()).hexdigest()))
write('asset-manifest.json',m)
readme='''# 英语课堂电子桌游 · 第一轮设计交付

版本：2026-10-12-round1。对应App v0.7之后的阶段2 PVE设计，**不是App更新或IPA**。玩法与数值仍以原需求和GameCore为准。

- 方向A「晨光森林」：苔绿披风、温暖光感、奶油白玻璃面板。
- 方向B「晴空学园」：湖蓝披风、清爽剪裁、同一套操作与资源语义。
- **两方向都尚未由教师确认。** 不把A的先列出顺序当作已选择审美。正式批量头像在方向确认后制作。

## 先看什么

打开 `previews/index.html` 可本地离线浏览；也可直接查看PNG。13张预览包括：两套风格板、每套教师战斗与公开16:9/4:3、组件状态板、公开绘本状态条16:9/4:3、特殊结算与隐私板、7角色+3怪物密度检查。

教师PNG2732×2048对应1366×1024逻辑点。公开战斗1920×1080及1440×1080重新排版。12汉字和24英文姓名全长保留，主持人是第七个角色。当前行动者A与奖励对象B/C分别标记。

## 可交给开发的文件

| 文件/目录 | 内容 |
|---|---|
| design-tokens.json | 语义颜色、系统字体、字号、间距、材质、触区、动效、三尺寸布局 |
| asset-manifest.json | 原清单ID和制作状态；样稿A/B显式变体；6个原创资源图标 |
| assets/style_a、style_b | 每方向冒险者和史莱姆，4张1024×1024独立透明PNG |
| assets/icons | 生命/护盾/AP/金币/积分/倒地6套SVG+256透明PNG |
| sources | 可编辑SVG页面、生成原图、导出画布、演示数据、生成/导出脚本 |
| annotations | 规则、组件、交互、原生接入、适配、验收、材质与授权说明 |

**PNG整页是设计演示；禁止作为App整页背景。** 正式姓名、数字、按钮和节点道路由App叠加。样稿头像不含姓名、队伍、生命数字；其余职业用中性模板占位，并未擅自设计新职业。

## 制作范围与后续

本轮A完成风格与布局；提前交少量B样稿和资源图标。待确认后按ID扩展4职业及6怪物：adventurer/ranger/spellblade/dragonKnight；slime/wolf/goblinArcher/stoneGuardian/caveTroll/ruinDragon。18物品、套装、正式地图装饰仍列为C/D后续，未伪称已生成。

公开绘本稿使用占位页，仅检查六字段和无AP、16:9等比完整容纳；没有教师实际PPTX，不能代替离线导入或电视远距离实测。教师绘本整页、后台、背包/商店、历史与结算整页留后续阶段。

## 状态与规则

大面板采用系统毛玻璃，静态SVG以浅色渐变近似；真正模糊与液态玻璃需原生实现后核对。小控件可采用系统液态玻璃或纯色；高频执行始终文字清楚。正文不使用像素字体。

地图仍为节点/道路，PVE沿用地图。选动作/目标不扣费；执行一次才提交。自然20、伤害、自疗、护盾、掉落、积分和结束皆读取一次已提交结果。备注、选奖和隐藏节点内容只在教师侧；绘本公开状态没有AP。

## 真实检查与限制

已核对模板ID、演示数据、PNG尺寸和透明边距、布局文本边界和5%公开安全区、文字颜色对比度；检查证据见 `annotations/07_validation.md`。没有在用户iPad/实际电视/Xcode27运行本设计，不宣称原生材质、点击效率、无线隐私、观看距离或PPTX导入已验证。当前公开投影欠缺结果摘要和细粒度状态，需开发对话按最小公开字段补充。

本交付只写 `design/` 独立分支，不更改App、GameCore、main或工作流。已有仓库存档脚本要求IPA和归档分支；本次用户限定设计目录优先，采用design目录内ZIP、逐文件SHA256清单与独立设计标签，不生成虚假的编译记录。

来源与授权见 `annotations/06_materials_and_license.md`。没有在线字体或素材依赖。最终批量制作不根据教师未回复自动修改玩法。
'''
write('README.md',readme)
write('annotations/06_materials_and_license.md','''# 材质、颜色、字体与独立资产

## 原生实现映射

大面积信息框使用SwiftUI `.regularMaterial`，圆角16、浅色边缘1–2点。以明亮界面为基准，不强制全App忽略无障碍系统设置。素材装饰限制对比度，数字区域保留暖白底衬；降低透明度时改为surface纯色。PNG/SVG预览只表现磨砂材质的层次和色调，不能烘焙假模糊作为运行时背景。

小按钮可用iPadOS27系统液态玻璃；主执行采用primary纯色+白字、选中绿边、选奖金边+勾。触区>=44×44pt；主按钮56高；禁用保留明确原因。面板与按钮内边距16，外边距24，间距8/12/16/24/32；面板圆角16、按钮12、徽章8。4:3是重排，不做水平缩放。

## 颜色语义

| 令牌 | 色值 | 用途与标记 |
|---|---|---|
| background | #F5F1E8 | 暖白底 |
| ink | #183B36 | 主文字 |
| muted | #526B64 | 说明 |
| primary | #176B5B | 执行/当前行动；行动中文字+边框 |
| accent | #995207 | 发奖对象/暂停；勾选/文字 |
| danger | #B93838 | 生命危险、受击、倒地；倒地文字/姿态 |
| shield | #315E9C | 护盾，独立于生命 |
| action | #6650A4 | AP行动点 |
| teamBlue / teamOrange / teamViolet | #315E9C / #995207 / #6650A4 | 队名+圆/菱/三角；可扩展更多队伍 |

金币用圆币图标+金币数，积分用星形图标+积分数；不以金币代积分。正式组件绑定assets/icons的语义ID，常规工具按钮使用本地SF Symbols。队伍和资源标签属于不同语义，颜色可相近但标签和图标不能省略。

## 字体

原生使用系统字体与中文系统回退，数字monospacedDigit。教师正文18、长名17、次要15、标题28；公开资源26、姓名28、队列24、提示44、焦点根据空间40–56。数字等宽，正文抗锯齿；像素质感只用于角色/装饰。

预览使用机器已安装Noto Sans CJK SC，属于SIL Open Font License 1.1，来源：https://github.com/notofonts/noto-cjk 。本交付不分发字体文件，App无需安装它，不加载网络字体。SF Symbols属于Apple系统能力，遵循Apple许可，不另导出为本包自制图标。

## 资产来源

4张职业/怪物样稿由本对话image_gen按原创文字描述生成。未提供或复制八方旅人的人物、画面或游戏文件；只探索HD像素的层次与光感。使用按OpenAI服务适用条款执行，不声明作品独占权。生成原图保存在sources，独立运行PNG通过标准画布导出为1024×1024；造型未重绘。PNG sRGB、RGBA、14%画布安全边距；不含姓名、数字、卡框或队伍。

6个SVG资源图标、页面SVG和低对比度像素轮廓由本交付原创几何绘制，可随本项目本地使用、修改。配色和图形不是既有游戏素材。未知地图节点只画统一轮廓与问号，装饰不传递Boss/奖励信息。

其他职业与怪物占位为中性字形徽章，不是完整职业/怪物头像。正式背景插画、18物品、地图地点图仍待后续批次。每项状态以asset-manifest.json为准。
''')
# Align supplementary storybook proof and fixed coordinates with the rendered sources.
p=R/'annotations/03_layout_and_adaptation.md';s=p.read_text().replace('角色第二行 | y898','角色第二行 | y902').replace('3张卡，居中','3张卡，左对齐，第四格为资源图例').replace('## 6. 本轮未交整页的绘本适配约束','## 6. 本轮补充的公开绘本状态条检查').replace('上述绘本约束列为后续接入验收，不能把本轮战斗页截一张去掉AP当成已验证的正式绘本页。','本轮另交public_storybook_16x9/4x3占位绘本页，检查7角色六字段与AP隐藏、等比页面区域。未交实际PPTX，教师绘本页和备注滚动仍需后续原生验收。');p.write_text(s)
p=R/'sources/demo-scenarios.json';d=json.loads(p.read_text());d['storybookSeven']['teacherNotes']='教师专属独立滚动；本轮另有公开绘本占位页与7角色无AP状态条检查稿，不代表实际PPT导入验证。';write('sources/demo-scenarios.json',d)
idx=json.loads((R/'sources/preview-index.json').read_text())
items=''.join(f'<figure><a href="{p["name"]}.png"><img loading="lazy" src="{p["name"]}.png" alt="{html.escape(p["label"])}"></a><figcaption>{html.escape(p["label"])} · <a href="../sources/{p["name"]}.svg">可编辑SVG</a></figcaption></figure>' for p in idx)
write('previews/index.html','<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>课堂桌游｜第一轮设计交接</title><style>body{margin:0;background:#f5f1e8;color:#183b36;font:18px system-ui;padding:24px}header{max-width:1200px;margin:auto}figure{margin:32px auto;max-width:1200px}img{width:100%;height:auto;border-radius:16px;box-shadow:0 5px 24px #183b3614}a{color:#176b5b}figcaption{padding:12px 0}h1{font-size:30px}</style><header><h1>英语课堂电子桌游 · 第一轮设计</h1><p>A晨光森林 / B晴空学园，方向待确认。离线交接预览，非App。</p><p><a href="../README.md">交付说明</a> · <a href="../asset-manifest.json">资产清单</a> · <a href="../design-tokens.json">设计令牌</a></p></header>'+items+'</html>')
print('Wrote tokens, manifest, README, materials and offline gallery')
