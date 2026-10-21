import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_lang.dart';
import '../services/shop_service.dart';
import '../theme.dart';

/// "Tienda": Lo De Lalo's catalog, the same products as on the website,
/// ordered by WhatsApp.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, this.service});

  final ShopService? service;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late final _service = widget.service ?? ShopService.instance;
  ShopCatalog? _catalog;
  String? _error;
  bool _loading = true;
  String _query = '';
  String? _category;

  @override
  void initState() {
    super.initState();
    _service.cached().then((c) {
      if (mounted && c != null && _catalog == null) setState(() => _catalog = c);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _service.fetch();
      if (mounted) setState(() => _catalog = catalog);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  void _whatsApp(ShopInfo shop, String text) => launchUrl(
        Uri.https('wa.me', '/${shop.whatsapp}', {'text': text}),
        mode: LaunchMode.externalApplication,
      );

  void _showProduct(ShopInfo shop, ShopProduct p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.imageUrl != null)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(p.imageUrl!, height: 220, fit: BoxFit.contain),
                  ),
                ),
              const SizedBox(height: 12),
              Text(p.name, style: Theme.of(ctx).textTheme.titleLarge),
              if (p.brand.isNotEmpty) Text(p.brand),
              const SizedBox(height: 6),
              Text(
                p.priceLabel,
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                      color: Brand.red,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (p.promoText.isNotEmpty) Text(p.promoText, style: const TextStyle(color: Brand.orange)),
              if (!p.inStock)
                Text(tr('Sin stock por ahora: consultá'), style: TextStyle(color: Colors.grey)),
              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(p.description),
              ],
              const SizedBox(height: 16),
              if (shop.whatsapp.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(p.inStock ? tr('Pedir por WhatsApp') : tr('Consultar por WhatsApp')),
                    onPressed: () => _whatsApp(
                      shop,
                      'Hola! Quiero pedir ${p.name} (${p.priceLabel}). Lo vi en PetTime.',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return Scaffold(
      appBar: AppBar(
        title: Text(catalog?.shop.name ?? tr('Tienda')),
        actions: [
          if (catalog != null && catalog.shop.catalogUrl.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.public),
              tooltip: tr('Ver el catálogo en la web'),
              onPressed: () => _open(catalog.shop.catalogUrl),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: catalog == null
            ? ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    Text(_error ?? tr('No se pudo cargar la tienda'), textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: Text(tr('Reintentar'))),
                  ],
                ],
              )
            : _body(catalog),
      ),
    );
  }

  Widget _body(ShopCatalog catalog) {
    final shop = catalog.shop;
    final q = _query.trim().toLowerCase();
    final products = catalog.products.where((p) {
      if (_category != null && p.category != _category) return false;
      if (q.isEmpty) return true;
      return '${p.name} ${p.brand} ${p.category}'.toLowerCase().contains(q);
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (shop.address.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.storefront_outlined, color: Brand.teal),
                        const SizedBox(width: 8),
                        Expanded(child: Text(shop.address)),
                      ],
                    ),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (shop.whatsapp.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.chat_outlined),
                          label: Text(tr('Consultar')),
                          onPressed: () => _whatsApp(shop, 'Hola! Tengo una consulta. Te escribo desde PetTime.'),
                        ),
                      if (shop.catalogUrl.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.public),
                          label: Text(tr('Catálogo web')),
                          onPressed: () => _open(shop.catalogUrl),
                        ),
                      if (shop.lostPetsUrl.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.campaign_outlined),
                          label: Text(tr('Perdidas en la web')),
                          onPressed: () => _open(shop.lostPetsUrl),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: tr('Buscar alimento, piedras, juguetes…'),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
        if (catalog.categories.length > 1)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final c in [null, ...catalog.categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(c == null ? tr('Todo') : _capitalize(c)),
                        selected: _category == c,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tr('Sin conexión: mostramos el catálogo guardado.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        if (products.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(tr('No hay productos que coincidan'), textAlign: TextAlign.center),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 16 + MediaQuery.viewPaddingOf(context).bottom),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.62,
            ),
            itemCount: products.length,
            itemBuilder: (_, i) => _ProductTile(
              product: products[i],
              onTap: () => _showProduct(shop, products[i]),
            ),
          ),
        ),
      ],
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});

  final ShopProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.white,
                      child: product.imageUrl == null
                          ? const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey)
                          : Image.network(
                              product.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.inventory_2_outlined,
                                size: 48,
                                color: Colors.grey,
                              ),
                            ),
                    ),
                  ),
                  if (product.promoText.isNotEmpty)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _Tag(text: product.promoText, color: Brand.orange),
                    ),
                  if (!product.inStock)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: _Tag(text: tr('Sin stock'), color: Colors.grey),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    product.priceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Brand.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Text(
          text,
          maxLines: 1,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
}
