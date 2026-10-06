const allSourcesEnabled = bool.fromEnvironment('ALL_SOURCES');
const appName = allSourcesEnabled ? '真果鉴' : '绿果鉴';
const appSlug = allSourcesEnabled ? 'zhenguojian' : 'lvguojian';

/// 真果鉴安装后先以绿果鉴出现，出现分级限制按钮（完整模式）后才是真果鉴。
String appEditionName(bool fullMode) =>
    allSourcesEnabled && fullMode ? '真果鉴' : '绿果鉴';
