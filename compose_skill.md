# Android - Jetpack Compose

Modern declarative UI toolkit for building native Android interfaces.

## Project Stack

- **Compose BOM**: 2025.12.01
- **Navigation**: Navigation3 (androidx.navigation3)
- **DI**: Hilt with `hiltViewModel()`
- **Image Loading**: Coil 3.x
- **State Management**: `mutableStateOf` in ViewModel + `derivedStateOf` for computed state

## Key Concepts

### State Management

Compose provides several ways to manage state:

- **remember**: Survives recomposition
- **rememberSaveable**: Survives configuration changes
- **mutableStateOf**: Creates observable state (primary approach in this project)
- **derivedStateOf**: Computed state that updates when dependencies change
- **snapshotFlow**: Convert Compose state to Flow

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

// With saveable for configuration changes
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

### ViewModel State Pattern (Project Standard)

This project uses `mutableStateOf` directly in ViewModel for UI state:

```kotlin
@HiltViewModel
class MainViewModel @Inject constructor(
    private val interstitialAd: MyGlobalInterstitialAd,
    private val toastManager: ToastManager,
    @ApplicationContext val appContext: Context
) : BaseViewModel() {
    // Direct mutable state in ViewModel
    var background by mutableStateOf<Color>(BackgroundColor)
    var updateDialogState by mutableStateOf(false)
    var permissionCardState by mutableStateOf(false)
    
    // StateFlow for streams that need collection
    val interstitialAdFlow = MutableSharedFlow<Boolean>()
}

@Composable
fun MainScreen(viewModel: MainViewModel = hiltViewModel()) {
    // Directly access ViewModel state - automatically triggers recomposition
    val background = viewModel.background
    
    Box(modifier.background(background)) {
        // UI content
    }
}
```

### derivedStateOf for Computed State

Use `derivedStateOf` when computing values from other states:

```kotlin
@Composable
private fun NavBar(
    topLevelBackStack: TopLevelBackStack<Any>,
    click: (NaviTab) -> Unit
) {
    // Efficient recomputation only when topLevelKey changes
    val visible by remember(topLevelBackStack.topLevelKey) {
        derivedStateOf { !topLevelBackStack.nowTaskSizeGreaterThan() }
    }
    
    AnimatedVisibility(visible = visible) {
        // Navigation content
    }
}
```

### UI Data Class Pattern (@Stable)

Project standard for UI data classes with mutable state:

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

Guidelines:

- Use `@Stable` annotation for data classes used in Compose
- Use `val` for immutable parameters
- Use `mutableStateOf` for mutable parameters (suffix with `State`)
- Initialize state from constructor parameter

## Navigation3 Pattern

This project uses Navigation3 instead of Navigation Compose:

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

## State Hoisting

Lift state up to make composables stateless and reusable:

```kotlin
// Stateless composable
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

// Stateful parent
@Composable
fun UserForm() {
    var name by remember { mutableStateOf("") }

    NameInput(
        name = name,
        onNameChange = { name = it }
    )
}
```

## Best Practices

### Composable Function Guidelines

```kotlin
// Use Modifier as first optional parameter
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

// Use slot APIs for flexible content
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

### Efficient Recomposition

```kotlin
// Use keys for list items with Paging
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
                // Item content
            }
        }
    }
}

// Use derivedStateOf for expensive computations
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

### Side Effects

```kotlin
// LaunchedEffect for coroutine-based side effects
@Composable
fun UserProfile(userId: String, viewModel: UserViewModel) {
    LaunchedEffect(userId) {
        viewModel.loadUser(userId)
    }

    // UI content
}

// DisposableEffect for cleanup
@Composable
fun LifecycleAwareComponent(lifecycle: Lifecycle) {
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            // Handle lifecycle events
        }
        lifecycle.addObserver(observer)

        onDispose {
            lifecycle.removeObserver(observer)
        }
    }
}

// SideEffect for non-suspend side effects
@Composable
fun AnalyticsScreen(screenName: String) {
    SideEffect {
        analytics.logScreenView(screenName)
    }
}

// snapshotFlow for converting Compose state to Flow
@Composable
fun BackStackObserver(backStack: TopLevelBackStack<Any>) {
    LaunchedEffect(Unit) {
        snapshotFlow {
            val key = backStack.topLevelKey
            val top = backStack.getTopLeveTaskContent(key)?.lastOrNull()
            key to top
        }.distinctUntilChanged()
            .collect { (key, topEntry) ->
                // Handle navigation changes
            }
    }
}
```

## Common Patterns

### Material 3 Theming

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

// Using theme values
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

### Lists and Grids

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

// Sticky headers
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

// Create composition local for shared transition scope
val LocalSharedTransitionScope = compositionLocalOf<SharedTransitionScope?> { null }
```

## Anti-Patterns

### Avoid Side Effects in Composition

Bad:

```kotlin
@Composable
fun BadExample(viewModel: ViewModel) {
    viewModel.loadData()  // Called on every recomposition!

    Text("Data loaded")
}
```

Good:

```kotlin
@Composable
fun GoodExample(viewModel: ViewModel) {
    LaunchedEffect(Unit) {
        viewModel.loadData()
    }

    Text("Data loaded")
}
```

### Don't Read State in Remember Block

Bad:

```kotlin
@Composable
fun BadCounter(initial: Int) {
    // Won't update when initial changes
    var count by remember { mutableStateOf(initial) }
}
```

Good:

```kotlin
@Composable
fun GoodCounter(initial: Int) {
    var count by remember(initial) { mutableStateOf(initial) }
}
```

### Avoid Heavy Computation During Composition

Bad:

```kotlin
@Composable
fun BadList(items: List<Item>) {
    // Runs on every recomposition
    val sorted = items.sortedBy { it.name }
    LazyColumn { /* ... */ }
}
```

Good:

```kotlin
@Composable
fun GoodList(items: List<Item>) {
    val sorted by remember(items) {
        derivedStateOf { items.sortedBy { it.name } }
    }
    LazyColumn { /* ... */ }
}
```

### Don't Use StateFlow in ViewModel for Simple UI State

Bad (overly complex for simple state):

```kotlin
class BadViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()
    
    fun updateName(name: String) {
        _uiState.update { it.copy(name = name) }
    }
}
```

Good (project standard):

```kotlin
class GoodViewModel : ViewModel() {
    var name by mutableStateOf("")
        private set
    
    fun updateName(newName: String) {
        name = newName
    }
}
```

## Related Skills

- **android-architecture**: MVI and clean architecture patterns
- **android-kotlin-coroutines**: Async operations in Compose
- **compose-ui-data**: UI data class patterns with @Stable annotation

