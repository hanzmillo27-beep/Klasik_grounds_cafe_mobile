import 'package:flutter/material.dart';

import '../controller/cafe_controller.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/cafe_logo.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.session, required this.onExit});

  final CafeSession? session;
  final VoidCallback onExit;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ApiService _service;
  late final CafeController _controller;
  int _selectedIndex = 0;

  static const _allDestinations = [
    _Destination('Overview', Icons.grid_view_rounded, 0),
    _Destination('Our menu', Icons.local_cafe_outlined, 1),
    _Destination('Kiosk order', Icons.shopping_bag_outlined, 2),
    _Destination('Inventory', Icons.inventory_2_outlined, 3),
    _Destination('Rewards', Icons.loyalty_outlined, 4),
  ];

  static const _staffRoles = {'owner', 'cashier', 'staff'};

  bool get _isStaff => _staffRoles.contains(widget.session?.role);
  bool get _isLoyalCustomer => widget.session?.role == 'loyal_customer';
  bool get _isKioskCustomer =>
      widget.session == null || widget.session?.role == 'user';

  List<_Destination> get _destinations {
    if (_isStaff) {
      return [_allDestinations[0], _allDestinations[1], _allDestinations[3]];
    }
    if (_isLoyalCustomer) {
      return [_allDestinations[2], _allDestinations[4]];
    }
    return _isKioskCustomer ? [_allDestinations[2]] : const [];
  }

  @override
  void initState() {
    super.initState();
    _service = ApiService(sessionCookie: widget.session?.sessionCookie);
    _selectedIndex = _isStaff ? 0 : 2;
    _controller = CafeController(service: _service, session: widget.session)
      ..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          if (_destinations.isEmpty) {
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'This account role is not enabled in the cafe app.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _signOut,
                        child: const Text('Return to sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final wide = constraints.maxWidth >= 980;
          return Scaffold(
            body: SafeArea(
              child: wide
                  ? Row(
                      children: [
                        _Sidebar(
                          selectedIndex: _selectedIndex,
                          destinations: _destinations,
                          onSelect: _selectPage,
                          onSignOut: _signOut,
                          memberName: _controller.profile.fullName,
                          isGuest: _controller.isGuest,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              _TopBar(
                                selectedIndex: _selectedIndex,
                                memberName: _controller.profile.fullName,
                                points: _isLoyalCustomer
                                    ? _controller.profile.loyaltyPoints
                                    : null,
                              ),
                              Expanded(child: _pageBody(wide: true)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _MobileHeader(
                          memberName: _controller.profile.fullName,
                          points: _isLoyalCustomer
                              ? _controller.profile.loyaltyPoints
                              : null,
                          onSignOut: _signOut,
                          isGuest: _controller.isGuest,
                        ),
                        Expanded(child: _pageBody(wide: false)),
                      ],
                    ),
            ),
            bottomNavigationBar: wide || _destinations.length < 2
                ? null
                : _BottomNav(
                    selectedIndex: _destinations.indexWhere(
                      (item) => item.pageIndex == _selectedIndex,
                    ),
                    destinations: _destinations,
                    onSelect: (index) =>
                        _selectPage(_destinations[index].pageIndex),
                  ),
          );
        },
      ),
    );
  }

  Widget _pageBody({required bool wide}) {
    if (_controller.loading) {
      return const Center(child: CircularProgressIndicator(color: forest));
    }
    if (_controller.errorMessage != null) {
      return _SetupError(
        message: _controller.errorMessage!,
        onRetry: _controller.load,
      );
    }
    switch (_selectedIndex) {
      case 1:
        return _MenuPage(controller: _controller);
      case 2:
        return _KioskPage(controller: _controller, wide: wide);
      case 3:
        return _InventoryPage(controller: _controller);
      case 4:
        return _RewardsPage(controller: _controller);
      default:
        return _OverviewPage(
          controller: _controller,
          onOpenMenu: () => _selectPage(1),
        );
    }
  }

  void _selectPage(int index) {
    if (!_destinations.any((destination) => destination.pageIndex == index)) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _signOut() => widget.onExit();
}

class _Destination {
  const _Destination(this.label, this.icon, this.pageIndex);
  final String label;
  final IconData icon;
  final int pageIndex;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
    required this.onSignOut,
    required this.memberName,
    required this.isGuest,
  });

  final int selectedIndex;
  final List<_Destination> destinations;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignOut;
  final String memberName;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 23, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 3, 8, 32),
            child: _BrandMark(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                color: mutedInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(destinations.length, (index) {
            final item = destinations[index];
            final selected = item.pageIndex == selectedIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Material(
                color: selected ? const Color(0xFFEDF2ED) : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => onSelect(item.pageIndex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          size: 19,
                          color: selected ? forest : mutedInk,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected ? forest : const Color(0xFF626C64),
                          ),
                        ),
                        if (item.pageIndex == 2) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? forest
                                  : const Color(0xFFF0F0EA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'KIOSK',
                              style: TextStyle(
                                fontSize: 8,
                                letterSpacing: .5,
                                color: selected ? Colors.white : mutedInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cream,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                const _Avatar(size: 37),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memberName.isEmpty ? 'Cafe member' : memberName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isGuest ? 'Guest kiosk' : 'Klasik Grounds',
                        style: TextStyle(color: mutedInk, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onSignOut,
                  tooltip: isGuest ? 'Return to sign in' : 'Sign out',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 17,
                    color: mutedInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selectedIndex,
    required this.memberName,
    required this.points,
  });
  final int selectedIndex;
  final String memberName;
  final int? points;

  @override
  Widget build(BuildContext context) => Container(
    height: 78,
    padding: const EdgeInsets.symmetric(horizontal: 32),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFEDEEE8))),
    ),
    child: Row(
      children: [
        Text(
          _pageTitle(selectedIndex),
          style: const TextStyle(
            fontSize: 17,
            color: ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (points != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E9),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, size: 17, color: accent),
                const SizedBox(width: 7),
                Text(
                  '${points!} pts',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 14),
        _Avatar(size: 38, name: memberName),
      ],
    ),
  );
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.memberName,
    required this.points,
    required this.onSignOut,
    required this.isGuest,
  });
  final String memberName;
  final int? points;
  final VoidCallback onSignOut;
  final bool isGuest;

  @override
  Widget build(BuildContext context) => Container(
    height: 70,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFEDEEE8))),
    ),
    child: Row(
      children: [
        const _BrandMark(compact: true),
        const Spacer(),
        if (points != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E9),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, size: 16, color: accent),
                const SizedBox(width: 5),
                Text(
                  '${points!}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuButton<String>(
          tooltip: 'Account menu',
          onSelected: (value) {
            if (value == 'signout') onSignOut();
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              value: 'email',
              enabled: false,
              child: Text(memberName.isEmpty ? 'Cafe member' : memberName),
            ),
            PopupMenuItem(
              value: 'signout',
              child: Text(isGuest ? 'Return to sign in' : 'Sign out'),
            ),
          ],
          child: const Padding(
            padding: EdgeInsets.only(left: 10),
            child: _Avatar(size: 35),
          ),
        ),
      ],
    ),
  );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
  });
  final int selectedIndex;
  final List<_Destination> destinations;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: onSelect,
    backgroundColor: Colors.white,
    indicatorColor: const Color(0xFFEAF0EA),
    height: 68,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    destinations: destinations
        .map(
          (item) => NavigationDestination(
            icon: Icon(item.icon, size: 21),
            selectedIcon: Icon(item.icon, size: 21, color: forest),
            label: item.label == 'Kiosk order' ? 'Kiosk' : item.label,
          ),
        )
        .toList(),
  );
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.controller, required this.onOpenMenu});
  final CafeController controller;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final firstName = controller.profile.fullName.trim().split(' ').first;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 27, 30, 38),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting${firstName.isEmpty ? '' : ', $firstName'}',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Your cafe, your way. Here’s what’s happening today.',
                  ),
                ],
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 760)
              OutlinedButton.icon(
                onPressed: onOpenMenu,
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('Browse menu'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: forest,
                  side: const BorderSide(color: Color(0xFFD8DED6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 14,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            if (controller.canViewRecentOrders)
              _MetricCard(
                icon: Icons.shopping_bag_outlined,
                title: 'Recent orders',
                value: controller.recentOrdersErrorMessage == null
                    ? '${controller.recentOrders.length}'
                    : '—',
                tone: const Color(0xFFE9F0E8),
              ),
            _MetricCard(
              icon: Icons.coffee_outlined,
              title: 'Menu favorites',
              value: '${controller.products.length}',
              tone: const Color(0xFFFFF1E5),
            ),
            _MetricCard(
              icon: Icons.inventory_2_outlined,
              title: 'Out of stock',
              value: '${controller.lowStockCount}',
              tone: const Color(0xFFF9EAE4),
            ),
          ],
        ),
        const SizedBox(height: 30),
        _SectionHeading(
          title: 'Popular at Klasik',
          action: 'View full menu',
          onAction: onOpenMenu,
        ),
        const SizedBox(height: 15),
        _ProductGrid(
          controller: controller,
          products: controller.products.take(3).toList(),
          onAdded: (_) {},
          shrinkWrap: true,
          showAddButton: false,
        ),
        if (controller.canViewRecentOrders) ...[
          const SizedBox(height: 30),
          _SectionHeading(
            title: 'Recent orders',
            action: controller.refreshingRecentOrders
                ? 'Refreshing...'
                : 'Refresh',
            onAction: controller.refreshingRecentOrders
                ? null
                : controller.refreshRecentOrders,
          ),
          const SizedBox(height: 12),
          if (controller.recentOrdersErrorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Could not load recent orders. ${controller.recentOrdersErrorMessage}',
                style: const TextStyle(color: accent),
              ),
            ),
          if (controller.recentOrders.isNotEmpty ||
              (controller.recentOrdersErrorMessage == null &&
                  !controller.refreshingRecentOrders))
            _RecentOrders(orders: controller.recentOrders),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.tone,
  });
  final IconData icon;
  final String title;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 195,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEDE7)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: forest, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: mutedInk, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MenuPage extends StatefulWidget {
  const _MenuPage({required this.controller});
  final CafeController controller;

  @override
  State<_MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<_MenuPage> {
  String _category = 'All';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final categories = [
      'All',
      ...widget.controller.products.map((item) => item.category).toSet(),
    ];
    final products = widget.controller.products.where((product) {
      final matchesCategory =
          _category == 'All' || product.category == _category;
      final matchesQuery = '${product.name} ${product.description}'
          .toLowerCase()
          .contains(_query.toLowerCase());
      return matchesCategory && matchesQuery;
    }).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 36),
      children: [
        Text(
          'Made for your moment',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 25),
        ),
        const SizedBox(height: 6),
        const Text('Small-batch coffee, comfort food, and little treats.'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: MediaQuery.sizeOf(context).width > 700
                  ? 285
                  : double.infinity,
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search the menu',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            ...categories.map(
              (category) => ChoiceChip(
                label: Text(category),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
                selectedColor: const Color(0xFFE6EDE6),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: _category == category
                      ? const Color(0xFFD3DED3)
                      : const Color(0xFFE7E8E2),
                ),
                labelStyle: TextStyle(
                  color: _category == category ? forest : mutedInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ProductGrid(
          controller: widget.controller,
          products: products,
          onAdded: (_) {},
          shrinkWrap: true,
          showAddButton: false,
        ),
        if (products.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('No items match that search.')),
          ),
      ],
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.controller,
    required this.products,
    required this.onAdded,
    this.shrinkWrap = false,
    this.compact = false,
    this.showAddButton = true,
  });

  final CafeController controller;
  final List<CafeProduct> products;
  final ValueChanged<CafeProduct> onAdded;
  final bool shrinkWrap;
  final bool compact;
  final bool showAddButton;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 850
          ? 3
          : constraints.maxWidth >= 520
          ? 2
          : 1;
      return GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        itemCount: products.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 13,
          mainAxisSpacing: 13,
          childAspectRatio: compact ? 1.12 : 0.88,
        ),
        itemBuilder: (context, index) {
          final product = products[index];
          return _ProductCard(
            product: product,
            quantity: controller.quantityFor(product),
            compact: compact,
            onAdd: showAddButton && product.isAvailable
                ? () {
                    controller.addToCart(product);
                    onAdded(product);
                  }
                : null,
          );
        },
      );
    },
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.quantity,
    required this.compact,
    required this.onAdd,
  });

  final CafeProduct product;
  final int quantity;
  final bool compact;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE8EAE3)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: compact ? 5 : 6,
          child: Container(
            width: double.infinity,
            color: _categoryTint(product.category),
            child: product.imageUrl == null || product.imageUrl!.isEmpty
                ? Icon(
                    _categoryIcon(product.category),
                    color: forest,
                    size: compact ? 31 : 40,
                  )
                : Image.network(
                    product.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      _categoryIcon(product.category),
                      color: forest,
                      size: compact ? 31 : 40,
                    ),
                  ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(compact ? 10 : 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.category.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: mutedInk,
                  fontSize: 9,
                  letterSpacing: .7,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _money(product.price),
                      style: const TextStyle(
                        color: forest,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!product.isAvailable)
                    const Text(
                      'Out of stock',
                      style: TextStyle(color: accent, fontSize: 9),
                    )
                  else if (quantity > 0)
                    Text(
                      '$quantity in order',
                      style: const TextStyle(color: forest, fontSize: 9),
                    ),
                  if (onAdd != null) ...[
                    const SizedBox(width: 5),
                    IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      tooltip: 'Add ${product.name}',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _KioskPage extends StatefulWidget {
  const _KioskPage({required this.controller, required this.wide});
  final CafeController controller;
  final bool wide;

  @override
  State<_KioskPage> createState() => _KioskPageState();
}

class _KioskPageState extends State<_KioskPage> {
  late final TextEditingController _customerNameController;

  @override
  void initState() {
    super.initState();
    _customerNameController = TextEditingController(
      text: widget.controller.session?.username ?? '',
    );
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final orderId = await widget.controller.submitOrder(
        customerName: _customerNameController.text,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Order placed: $orderId')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.orderErrorMessage ??
                'Could not place this order.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = widget.controller.lastOrderId;
    if (reference != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: forest, size: 56),
              const SizedBox(height: 16),
              Text(
                'Order submitted',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text('Show this reference to the cashier.'),
              const SizedBox(height: 16),
              SelectableText(
                reference,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              const Text('Your order is not paid yet. Pay at the cashier.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: widget.controller.startNewOrder,
                child: const Text('Start new order'),
              ),
            ],
          ),
        ),
      );
    }
    final products = _KioskProducts(controller: widget.controller);
    final cart = _CartPanel(
      controller: widget.controller,
      customerNameController: _customerNameController,
      onPlaceOrder: _placeOrder,
    );
    if (widget.wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: products),
            const SizedBox(width: 18),
            SizedBox(width: 330, child: cart),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          Expanded(flex: 6, child: products),
          const SizedBox(height: 12),
          Expanded(flex: 5, child: cart),
        ],
      ),
    );
  }
}

class _KioskProducts extends StatelessWidget {
  const _KioskProducts({required this.controller});
  final CafeController controller;

  @override
  Widget build(BuildContext context) {
    final products = controller.products
        .where((product) => product.isAvailable)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build your order',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontSize: 21),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Tap an item to add it to your bag.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width > 650) const _OpenBadge(),
            ],
          ),
        ),
        Expanded(
          child: _ProductGrid(
            controller: controller,
            products: products,
            compact: true,
            onAdded: (product) => _showAdded(context, product.name),
          ),
        ),
      ],
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.controller,
    required this.customerNameController,
    required this.onPlaceOrder,
  });
  final CafeController controller;
  final TextEditingController customerNameController;
  final VoidCallback onPlaceOrder;

  @override
  Widget build(BuildContext context) {
    final items = controller.cartProducts;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7E9E2)),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Your order',
                  style: TextStyle(
                    color: ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (controller.cartItemCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0EA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${controller.cartItemCount} items',
                    style: const TextStyle(
                      color: forest,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: customerNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name for this order',
              prefixIcon: Icon(Icons.person_outline, size: 19),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(
                              color: cream,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_bag_outlined,
                              color: forest,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Your cart is empty',
                            style: TextStyle(
                              color: ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Add an item from the menu to get started.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 17, color: Color(0xFFEDEEE8)),
                    itemBuilder: (context, index) {
                      final product = items[index];
                      final quantity = controller.quantityFor(product);
                      return Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _categoryTint(product.category),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _categoryIcon(product.category),
                              color: forest,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: ink,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _money(product.price * quantity),
                                  style: const TextStyle(
                                    color: mutedInk,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _QuantityControl(
                            quantity: quantity,
                            onAdd: () => controller.addToCart(product),
                            onRemove: () => controller.removeFromCart(product),
                            compact: true,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(height: 17, color: Color(0xFFEDEEE8)),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Subtotal',
                  style: TextStyle(fontSize: 12, color: mutedInk),
                ),
              ),
              Text(
                _money(controller.cartTotal),
                style: const TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: items.isEmpty || controller.placingOrder
                  ? null
                  : onPlaceOrder,
              icon: controller.placingOrder
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                controller.placingOrder
                    ? 'Placing order…'
                    : 'Place order · ${_money(controller.cartTotal)}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    this.compact = false,
  });
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4EF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QuantityIcon(
          icon: Icons.remove_rounded,
          onTap: onRemove,
          compact: compact,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 7),
          child: Text(
            '$quantity',
            style: const TextStyle(
              color: forest,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _QuantityIcon(icon: Icons.add_rounded, onTap: onAdd, compact: compact),
      ],
    ),
  );
}

class _QuantityIcon extends StatelessWidget {
  const _QuantityIcon({
    required this.icon,
    required this.onTap,
    required this.compact,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: compact ? 25 : 31,
      height: compact ? 27 : 32,
      child: Icon(icon, size: 14, color: forest),
    ),
  );
}

class _InventoryPage extends StatelessWidget {
  const _InventoryPage({required this.controller});
  final CafeController controller;

  @override
  Widget build(BuildContext context) {
    final low = controller.lowStockCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 27, 30, 38),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stockroom',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontSize: 25),
                  ),
                  const SizedBox(height: 5),
                  const Text('A clear view of what’s ready for today.'),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: low == 0
                    ? const Color(0xFFEAF2E9)
                    : const Color(0xFFFFF0E7),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text(
                low == 0 ? 'All stocked' : '$low need attention',
                style: TextStyle(
                  color: low == 0 ? forest : const Color(0xFF9A552E),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 21),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              icon: Icons.inventory_2_outlined,
              title: 'Tracked items',
              value: '${controller.inventory.length}',
              tone: const Color(0xFFE9F0E8),
            ),
            _MetricCard(
              icon: Icons.warning_amber_rounded,
              title: 'Out of stock',
              value: '$low',
              tone: const Color(0xFFFFF1E5),
            ),
            _MetricCard(
              icon: Icons.local_cafe_outlined,
              title: 'Menu items',
              value: '${controller.products.length}',
              tone: const Color(0xFFECEBF4),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE8EAE3)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(19, 17, 19, 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Inventory levels',
                        style: TextStyle(
                          color: ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${controller.inventory.length} products',
                      style: const TextStyle(color: mutedInk, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEDEEE8)),
              if (controller.inventory.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Text(
                    'No inventory records are available from the API.',
                  ),
                )
              else
                ...controller.inventory.map(
                  (item) => _InventoryRow(item: item),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 14),
    child: Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: _categoryTint(item.category),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_categoryIcon(item.category), size: 18, color: forest),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.category,
                style: const TextStyle(color: mutedInk, fontSize: 10),
              ),
            ],
          ),
        ),
        Text(
          '${_quantityLabel(item.quantity)}${item.unit.isEmpty ? '' : ' ${item.unit}'}',
          style: const TextStyle(
            color: ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 14),
        Container(
          width: 80,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: item.isLow
                ? const Color(0xFFFFF0E7)
                : const Color(0xFFEAF2E9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            item.isLow ? 'Out of stock' : 'In stock',
            style: TextStyle(
              color: item.isLow ? const Color(0xFF9A552E) : forest,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RewardsPage extends StatelessWidget {
  const _RewardsPage({required this.controller});
  final CafeController controller;

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 27, 30, 38),
      children: [
        Text(
          'Loyalty awards',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 25),
        ),
        const SizedBox(height: 6),
        const Text('Your current loyalty balance and recorded activity.'),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: forest,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CURRENT BALANCE',
                style: TextStyle(
                  color: Colors.white70,
                  letterSpacing: 1.2,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${profile.loyaltyPoints}',
                style: const TextStyle(
                  fontSize: 46,
                  height: 1,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Points in your loyalty account',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              icon: Icons.stars_rounded,
              title: 'Earning records',
              value: '${profile.earningsCount}',
              tone: const Color(0xFFECEBF4),
            ),
            _MetricCard(
              icon: Icons.redeem_outlined,
              title: 'Redemption records',
              value: '${profile.redemptionsCount}',
              tone: const Color(0xFFFFF1E5),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionHeading(title: 'Recent activity', action: null),
        const SizedBox(height: 12),
        if (profile.activity.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8EAE3)),
            ),
            child: const Text(
              'The current API does not include loyalty activity history.',
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8EAE3)),
            ),
            child: Column(
              children: [
                for (var index = 0; index < profile.activity.length; index++)
                  Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: profile.activity[index].isRedemption
                              ? const Color(0xFFFFF1E5)
                              : const Color(0xFFECEBF4),
                          child: Icon(
                            profile.activity[index].isRedemption
                                ? Icons.redeem_outlined
                                : Icons.stars_rounded,
                            color: forest,
                            size: 19,
                          ),
                        ),
                        title: Text(
                          profile.activity[index].title,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${profile.activity[index].detail} · ${profile.activity[index].createdAt.year == 1970 ? 'Date unavailable' : _dateLabel(profile.activity[index].createdAt.toLocal())}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      if (index != profile.activity.length - 1)
                        const Divider(
                          height: 1,
                          indent: 64,
                          endIndent: 16,
                          color: Color(0xFFEDEEE8),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8EAE3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: forest),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Your balance is loaded from the cafe loyalty API. Recent activity is not included in the supplied API responses.',
                  style: TextStyle(color: mutedInk, fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.orders});
  final List<CafeOrder> orders;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(23),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EAE3)),
        ),
        child: const Center(child: Text('No completed orders yet.')),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EAE3)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < orders.length; index++) ...[
            _OrderRow(order: orders[index]),
            if (index != orders.length - 1)
              const Divider(
                height: 1,
                indent: 17,
                endIndent: 17,
                color: Color(0xFFEDEEE8),
              ),
          ],
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});
  final CafeOrder order;

  @override
  Widget build(BuildContext context) {
    final createdAt = order.createdAt;
    final statusColor = order.status == 'completed' || order.status == 'ready'
        ? forest
        : const Color(0xFF9A552E);
    final statusTone = statusColor == forest
        ? const Color(0xFFEAF2E9)
        : const Color(0xFFFFF0E7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cream,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: forest,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order ${order.referenceCode.isEmpty ? '#${order.id}' : order.referenceCode}',
                  style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.itemCount} ${order.itemCount == 1 ? 'line item' : 'line items'} · '
                  '${createdAt == null ? 'Date unavailable' : _dateLabel(createdAt.toLocal())}',
                  style: const TextStyle(color: mutedInk, fontSize: 10),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: statusTone,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              order.status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 8,
                letterSpacing: .5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _money(order.total),
            style: const TextStyle(
              color: ink,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.action,
    this.onAction,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: ink,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: forest,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Row(
            children: [
              Text(
                action!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.arrow_forward_rounded, size: 14),
            ],
          ),
        ),
    ],
  );
}

class _SetupError extends StatelessWidget {
  const _SetupError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Container(
          padding: const EdgeInsets.all(27),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE8EAE3)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0E7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_outlined, color: accent),
              ),
              const SizedBox(height: 17),
              const Text(
                'Cafe data isn’t ready yet',
                style: TextStyle(
                  color: ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: mutedInk,
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 17),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cream,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Text(
                  'Check the Render API status and confirm this account has access to the requested endpoint. Guest menu browsing uses the public kiosk products route.',
                  style: TextStyle(color: forest, fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 19),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.size, this.name = ''});
  final double size;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'K' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFE9F0E8),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: forest,
          fontSize: size * .38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CafeLogo(size: compact ? 36 : 41),
      const SizedBox(width: 9),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KLASIK GROUNDS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: forest,
                fontWeight: FontWeight.w800,
                letterSpacing: .9,
                fontSize: compact ? 10 : 12,
              ),
            ),
            if (!compact)
              const Text(
                'CAFE  ·  ALL DAY, YOUR WAY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedInk,
                  letterSpacing: .8,
                  fontSize: 8,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _OpenBadge extends StatelessWidget {
  const _OpenBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2E9),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      children: [
        Icon(Icons.circle, color: Color(0xFF4D8B5C), size: 7),
        SizedBox(width: 6),
        Text(
          'OPEN',
          style: TextStyle(
            color: forest,
            fontSize: 9,
            letterSpacing: .7,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

String _money(double amount) => '₱${amount.toStringAsFixed(2)}';

String _quantityLabel(double amount) => amount % 1 == 0
    ? amount.toInt().toString()
    : amount
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

String _pageTitle(int index) => const [
  'Overview',
  'Our menu',
  'Kiosk order',
  'Inventory',
  'Loyalty awards',
][index];

String _dateLabel(DateTime date) {
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} today';
  }
  return '${date.day}/${date.month}/${date.year}';
}

Color _categoryTint(String category) {
  switch (category.toLowerCase()) {
    case 'coffee':
      return const Color(0xFFEAE0D4);
    case 'tea':
      return const Color(0xFFE6EFE4);
    case 'bakery':
      return const Color(0xFFFFEBCF);
    default:
      return const Color(0xFFE9EDF0);
  }
}

IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'coffee':
      return Icons.coffee_rounded;
    case 'tea':
      return Icons.emoji_food_beverage_rounded;
    case 'bakery':
      return Icons.bakery_dining_rounded;
    default:
      return Icons.restaurant_rounded;
  }
}

void _showAdded(BuildContext context, String name) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$name added to your order'),
        duration: const Duration(seconds: 1),
      ),
    );
}
