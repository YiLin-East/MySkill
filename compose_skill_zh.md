# Android - Jetpack Compose

用于构建原生 Android 界面的现代声明式 UI 工具包。

## 项目技术栈

- **Compose BOM**: 2025.12.01
- **导航**: Navigation3 (androidx.navigation3)
- **依赖注入**: Hilt 配合 `hiltViewModel()`
- **图片加载**: Coil 3.x
- **状态管理**: ViewModel 中使用 `mutableStateOf` + `derivedStateOf` 计算状态

## 核心概念

### 状态管理

Compose 提供了多种状态管理方式：

- **remember**: 在重组中保持状态
- **rememberSaveable**: 在配置变更中保持状态
- **mutableStateOf**: 创建可观察状态（本项目主要方式）
- **derivedStateOf**: 依赖变化时自动更新的计算状态
- **snapshotFlow**: 将 Compose 状态转换为 Flow

```kotlin
@Composable
fun Counter() {
    var count by remember { mutableStateOf(0) }

    Column {
        Text("Count: $count")
        Button(onClick = { count++ }) {
            Text("Increment")
        }
    }
}

// 使用 rememberSaveable 在配置变更中保持状态
@Composable
fun SearchField() {
    var query by rememberSaveable { mutableStateOf("") }

    TextField(
        value = query,
        onValueChange = { query = it },
        placeholder = { Text("Search...") }
    )
}
```

### ViewModel 状态模式（项目标准）

本项目在 ViewModel 中直接使用 `mutableStateOf` 管理 UI 状态：

```kotlin
@HiltViewModel
class MainViewModel @Inject constructor(
    private val interstitialAd: MyGlobalInterstitialAd,
    private val toastManager: ToastManager,
    @ApplicationContext val appContext: Context
) : BaseViewModel() {
    // 在 ViewModel 中直接定义可变状态
    var background by mutableStateOf<Color>(BackgroundColor)
    var updateDialogState by mutableStateOf(false)
    var permissionCardState by mutableStateOf(false)
    
    // StateFlow 用于需要收集的流数据
    val interstitialAdFlow = MutableSharedFlow<Boolean>()
}

@Composable
fun MainScreen(viewModel: MainViewModel = hiltViewModel()) {
    // 直接访问 ViewModel 状态 - 自动触发重组
    val background = viewModel.background
    
    Box(modifier.background(background)) {
        // UI 内容
    }
}
```

### derivedStateOf 用于计算状态

当需要从其他状态计算值时使用 `derivedStateOf`：

```kotlin
@Composable
private fun NavBar(
    topLevelBackStack: TopLevelBackStack<Any>,
    click: (NaviTab) -> Unit
) {
    // 仅在 topLevelKey 变化时重新计算
    val visible by remember(topLevelBackStack.topLevelKey) {
        derivedStateOf { !topLevelBackStack.nowTaskSizeGreaterThan() }
    }
    
    AnimatedVisibility(visible = visible) {
        // 导航内容
    }
}
```

### UI 数据类模式 (@Stable)

项目中带可变状态的 UI 数据类标准写法：

```kotlin
@Stable
data class LanguageSelectData(
    val id: Int,
    val languageTag: String,
    val countryLang: String,
    val transitionLang: String,
    private val select: Boolean
) {
    var selectState by mutableStateOf(select)
}

@Stable
data class GiftSheetData(
    val name: String,
    val giftId: Int,
    val thumbnailAddress: Any?,
    val price: Int,
    val intimacyValue: Int,
    val select: Boolean = false
) {
    var selectState by mutableStateOf(select)
}
```

规范指南：
- Compose 使用的数据类添加 `@Stable` 注解
- 不可变参数使用 `val`
- 可变参数使用 `mutableStateOf`（后缀加 `State`）
- 从构造函数参数初始化状态

## Navigation3 模式

本项目使用 Navigation3 而非传统的 Navigation Compose：

```kotlin
@Composable
fun MainScreen(mainViewModel: MainViewModel) {
    Box(modifier.background(BackgroundColor)) {
        NavDisplay(
            backStack = mainViewModel.topLevelBackStack.backStack,
            onBack = onBack,
            entryDecorators = listOf(
                rememberSaveableStateHolderNavEntryDecorator(),
                rememberViewModelStoreNavEntryDecorator(),
            ),
            transitionSpec = {
                fadeIn(animationSpec = tween(durationMillis = 120)) togetherWith
                    fadeOut(animationSpec = tween(durationMillis = 100))
            },
            entryProvider = entryProvider {
                entry(ChatTab) {
                    stateHolder.SaveableStateProvider("ChatTabRoot") {
                        ChatPermanentScreen(/* ... */)
                    }
                }
                
                entry<ChatPage>(metadata = iosNavSpec()) { key ->
                    ChatRoleScreen(
                        initModelId = key.initModelId,
                        initConversationIndex = key.initConversationIndex
                    )
                }
            }
        )
    }
}
```

## 状态提升

将状态提升到上层，使可组合函数无状态且可复用：

```kotlin
// 无状态可组合函数
@Composable
fun NameInput(
    name: String,
    onNameChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    TextField(
        value = name,
        onValueChange = onNameChange,
        label = { Text("Name") },
        modifier = modifier
    )
}

// 有状态的父组件
@Composable
fun UserForm() {
    var name by remember { mutableStateOf("") }

    NameInput(
        name = name,
        onNameChange = { name = it }
    )
}
```

## 最佳实践

### 可组合函数规范

```kotlin
// Modifier 作为第一个可选参数
@Composable
fun CustomCard(
    title: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit = {}
) {
    Card(
        modifier = modifier.clickable(onClick = onClick)
    ) {
        Text(
            text = title,
            modifier = Modifier.padding(16.dp)
        )
    }
}

// 使用 slot API 实现灵活内容
@Composable
fun CustomScaffold(
    topBar: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    content: @Composable (PaddingValues) -> Unit
) {
    Scaffold(
        topBar = topBar,
        bottomBar = bottomBar,
        content = content
    )
}
```

### 高效重组

```kotlin
// 配合 Paging 使用 key
@Composable
fun ChatList(
    pagerData: LazyPagingItems<TextChatAdapterData>,
    modelId: Int
) {
    LazyColumn {
        items(
            count = pagerData.itemCount,
            key = { index -> 
                pagerData.peek(index)?.let { data ->
                    "${modelId}_${index}_${data.id}"
                } ?: "${modelId}_${index}_empty"
            },
            contentType = pagerData.itemContentType() { /* ... */ }
        ) { index ->
            pagerData[index]?.let { data ->
                // 子项内容
            }
        }
    }
}

// 使用 derivedStateOf 进行复杂计算
@Composable
fun FilteredList(items: List<Item>, query: String) {
    val filteredItems by remember(items, query) {
        derivedStateOf {
            items.filter { it.name.contains(query, ignoreCase = true) }
        }
    }

    LazyColumn {
        items(filteredItems) { item ->
            ItemRow(item)
        }
    }
}
```

### 副作用处理

```kotlin
// LaunchedEffect 用于协程副作用
@Composable
fun UserProfile(userId: String, viewModel: UserViewModel) {
    LaunchedEffect(userId) {
        viewModel.loadUser(userId)
    }

    // UI 内容
}

// DisposableEffect 用于清理
@Composable
fun LifecycleAwareComponent(lifecycle: Lifecycle) {
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            // 处理生命周期事件
        }
        lifecycle.addObserver(observer)

        onDispose {
            lifecycle.removeObserver(observer)
        }
    }
}

// SideEffect 用于非挂起副作用
@Composable
fun AnalyticsScreen(screenName: String) {
    SideEffect {
        analytics.logScreenView(screenName)
    }
}

// snapshotFlow 将 Compose 状态转换为 Flow
@Composable
fun BackStackObserver(backStack: TopLevelBackStack<Any>) {
    LaunchedEffect(Unit) {
        snapshotFlow {
            val key = backStack.topLevelKey
            val top = backStack.getTopLeveTaskContent(key)?.lastOrNull()
            key to top
        }.distinctUntilChanged()
            .collect { (key, topEntry) ->
                // 处理导航变化
            }
    }
}
```

## 常见模式

### Material 3 主题

```kotlin
@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        darkTheme -> darkColorScheme(
            primary = Purple80,
            secondary = PurpleGrey80,
            tertiary = Pink80
        )
        else -> lightColorScheme(
            primary = Purple40,
            secondary = PurpleGrey40,
            tertiary = Pink40
        )
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}

// 使用主题值
@Composable
fun ThemedCard() {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Text(
            text = "Themed content",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
```

### 列表和网格

```kotlin
@Composable
fun ProductGrid(products: List<Product>) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 160.dp),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        items(products, key = { it.id }) { product ->
            ProductCard(product)
        }
    }
}

// 粘性头部
@Composable
fun ContactList(contacts: Map<Char, List<Contact>>) {
    LazyColumn {
        contacts.forEach { (initial, contactsForInitial) ->
            stickyHeader {
                Text(
                    text = initial.toString(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(16.dp),
                    style = MaterialTheme.typography.titleMedium
                )
            }
            items(contactsForInitial) { contact ->
                ContactItem(contact)
            }
        }
    }
}
```

### SharedTransitionLayout

```kotlin
@Composable
fun MainScreen() {
    Box(modifier.background(BackgroundColor)) {
        SharedTransitionLayout {
            CompositionLocalProvider(LocalSharedTransitionScope provides this) {
                NavContent(/* ... */)
            }
        }
    }
}

// 创建 composition local 用于共享过渡作用域
val LocalSharedTransitionScope = compositionLocalOf<SharedTransitionScope?> { null }
```

## 反模式

### 避免在组合中执行副作用

错误：

```kotlin
@Composable
fun BadExample(viewModel: ViewModel) {
    viewModel.loadData()  // 每次重组都会调用！

    Text("Data loaded")
}
```

正确：

```kotlin
@Composable
fun GoodExample(viewModel: ViewModel) {
    LaunchedEffect(Unit) {
        viewModel.loadData()
    }

    Text("Data loaded")
}
```

### 不要在 remember 块中读取状态

错误：

```kotlin
@Composable
fun BadCounter(initial: Int) {
    // initial 变化时不会更新
    var count by remember { mutableStateOf(initial) }
}
```

正确：

```kotlin
@Composable
fun GoodCounter(initial: Int) {
    var count by remember(initial) { mutableStateOf(initial) }
}
```

### 避免在组合期间进行复杂计算

错误：

```kotlin
@Composable
fun BadList(items: List<Item>) {
    // 每次重组都会执行
    val sorted = items.sortedBy { it.name }
    LazyColumn { /* ... */ }
}
```

正确：

```kotlin
@Composable
fun GoodList(items: List<Item>) {
    val sorted by remember(items) {
        derivedStateOf { items.sortedBy { it.name } }
    }
    LazyColumn { /* ... */ }
}
```

### 不要在 ViewModel 中对简单 UI 状态使用 StateFlow

错误（对简单状态过于复杂）：

```kotlin
class BadViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()
    
    fun updateName(name: String) {
        _uiState.update { it.copy(name = name) }
    }
}
```

正确（项目标准）：

```kotlin
class GoodViewModel : ViewModel() {
    var name by mutableStateOf("")
        private set
    
    fun updateName(newName: String) {
        name = newName
    }
}
```

## 相关技能

- **android-architecture**: MVVM 和 Clean Architecture 模式
- **android-kotlin-coroutines**: Compose 中的异步操作
- **compose-ui-data**: 使用 @Stable 注解的 UI 数据类模式
