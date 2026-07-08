---
name: android-compose-project
description: 面向 Android 项目的 Jetpack Compose 实现与审查技能。Use when building, modifying, or auditing Compose UI, ViewModel state, Navigation3 screens, side effects, Lazy lists, AndroidView/native ad wrappers, Material 3 theming, Hilt integration, or Coil image loading in a Kotlin Android project.
---

# Android Compose Project

使用这个技能时，先贴合当前仓库里的真实写法，再做 Compose 修改。不要把通用 Compose 示例直接套进项目。

## 工作流程

1. 先检查仓库。用 `rg` 查找现有 composable、ViewModel、导航入口、主题 token、图片加载封装，以及 Gradle 里可用的验证任务。
2. 以本地 Gradle 文件为准确认依赖栈。旧笔记里提到过 Compose BOM `2025.12.01`、Navigation3、Hilt、Coil 3.x、ViewModel `mutableStateOf`，但当前仓库文件才是事实来源。
3. 跟随附近代码风格。状态归属、参数顺序、命名、间距、颜色、动画写法，都优先匹配同模块现有模式。
4. 保持改动收敛。除非用户明确要求，不要顺手重构架构、把 Navigation3 换成 Navigation Compose，或替换整套状态管理方式。
5. 修改后运行最小但有效的验证，例如 `compileDebugKotlin`、相关模块测试、lint，或项目里已经使用的验证任务。

## Compose 状态

简单 UI 状态优先跟随项目里 ViewModel 直接持有 `mutableStateOf` 的模式：

```kotlin
class MainViewModel : ViewModel() {
    var updateDialogVisible by mutableStateOf(false)
        private set

    fun setUpdateDialogVisible(visible: Boolean) {
        updateDialogVisible = visible
    }
}
```

对事件流、仓库数据、需要 Flow 操作符处理的数据，或需要被收集的连续数据，再使用 `MutableStateFlow`、`StateFlow` 或 `SharedFlow`。

本地输入状态需要跨配置变更保留时使用 `rememberSaveable`。初始值可能变化时使用带 key 的 `remember(key)`。不要在无 key 的 `remember` 块里读取会变化的入参。

只有在值确实由其他状态派生，且避免重复计算有意义时才使用 `derivedStateOf`。不要为了形式把普通字符串或简单布尔读取也包进去。

## Composable API

除非附近代码有不同约定，优先使用这种参数形状：

```kotlin
@Composable
fun FeatureCard(
    title: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit = {}
) {
    Card(modifier = modifier.clickable(onClick = onClick)) {
        Text(text = title)
    }
}
```

规则：

- `modifier: Modifier = Modifier` 放在必需数据参数之后、默认回调之前。
- 可复用或需要测试的组件应做状态提升。
- 顶栏、底栏、列表项内容等可扩展区域优先用 slot API。
- 文案、尺寸、颜色、字体层级优先使用现有主题和项目常量。

## ViewModel UI 数据

如果 UI 数据类内部确实需要 Compose 可观察的可变状态，使用 `@Stable`、不可变构造参数，以及命名清晰的状态属性：

```kotlin
@Stable
data class LanguageSelectData(
    val id: Int,
    val languageTag: String,
    val countryLang: String,
    val transitionLang: String,
    private val selected: Boolean
) {
    var selectedState by mutableStateOf(selected)
}
```

新增这种数据结构前，先检查当前页面是否已经用不可变 UI state + copy 更新。已有局部模式优先。

## Navigation3

项目使用 `androidx.navigation3` 时，继续使用 Navigation3：

```kotlin
NavDisplay(
    backStack = viewModel.topLevelBackStack.backStack,
    onBack = onBack,
    entryDecorators = listOf(
        rememberSaveableStateHolderNavEntryDecorator(),
        rememberViewModelStoreNavEntryDecorator(),
    ),
    entryProvider = entryProvider {
        entry(ChatTab) {
            stateHolder.SaveableStateProvider("ChatTabRoot") {
                ChatPermanentScreen()
            }
        }
    }
)
```

规则：

- 新页面按同模块已有 route/key 风格接入。
- 保留既有 back stack 归属和 saveable state provider。
- 导航参数传 ID 或小型基础参数，避免传大型可变对象。
- 除非该区域已经混用，否则不要在 Navigation3 页面里引入 `NavHost` / `rememberNavController()`。

## 副作用

选择最窄的 effect API：

- `LaunchedEffect(key)`：绑定 key 的挂起任务。
- `DisposableEffect(key)`：监听器注册与释放。
- `SideEffect`：组合成功后的非挂起发布。
- `snapshotFlow`：需要把 Compose state 当作 Flow 观察时使用。

不要在 composable 函数体里直接调用 ViewModel 加载、导航、广告加载、埋点或权限请求。

## 列表与性能

处理 `LazyColumn`、`LazyVerticalGrid`、分页列表时：

- 有稳定身份时提供 stable key。
- 异构列表或分页列表在项目已有模式下提供 `contentType`。
- 排序、过滤、分组等较重计算不要直接放在组合体里；放到 ViewModel、`remember(keys)` 或必要的 `derivedStateOf` 中。
- 只有出现性能症状、或正在做性能审查时，才深入调整重组敏感的 callback 和 lambda。

## AndroidView 与原生 View

嵌入 `AndroidView`，尤其是广告 View 或共享 wrapper 时：

- 同时检查调用方约束和共享 wrapper 的 layout params。
- 原生广告 wrapper 如果应该按内容测量，高度优先使用 `WRAP_CONTENT`。
- 一个页面撑开、另一个页面正常时，先查共享 `AndroidView` factory 或内部 `ComposeView` 是否用了 `MATCH_PARENT`，不要先给单个调用方写死高度。
- 改布局时保留广告生命周期、加载回调、曝光与点击行为。

## Material 3 与图片

新增颜色、字体或 shape 前，先使用现有 `MaterialTheme`、项目颜色常量和 typography。使用 Coil 3.x 时，跟随本模块已有的 `AsyncImage`、image request、placeholder 和缓存写法。

## 收尾检查

结束前确认：

- 修改代码已编译，或说明为什么无法验证。
- 没有把副作用误放进组合过程。
- 状态只存活在需要的生命周期内。
- 导航返回行为和状态保存没有被破坏。
- UI 改动涉及布局时，小屏下文本和控件不溢出。
