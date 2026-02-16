import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/version.dart';
import '../services/version_service.dart';
import '../widgets/version_card.dart';

class VersionsScreen extends StatefulWidget {
  const VersionsScreen({super.key});

  @override
  State<VersionsScreen> createState() => _VersionsScreenState();
}

class _VersionsScreenState extends State<VersionsScreen> {
  final VersionService _versionService = VersionService();
  Future<List<Version>>? _versionsFuture;

  @override
  void initState() {
    super.initState();
    _versionsFuture = _versionService.loadVersions();
  }

  Future<void> _refreshVersions() async {
    _versionService.clearCache();
    setState(() {
      _versionsFuture = _versionService.loadVersions();
    });
    await _versionsFuture;
  }

  void _navigateToSubversions(Version version) {
    context.go('/story/${version.id}', extra: version);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('English 1999'),
      ),
      body: FutureBuilder<List<Version>>(
        future: _versionsFuture,
        builder: (context, snapshot) {
          // Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading versions...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          // Error state
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load versions',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      onPressed: () {
                        setState(() {
                          _versionsFuture = _versionService.loadVersions();
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          // Empty state
          final versions = snapshot.data ?? [];
          if (versions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.library_books_outlined,
                    size: 64,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No versions available',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            );
          }

          // Success state - Responsive Grid with max card size
          return RefreshIndicator(
            onRefresh: _refreshVersions,
            color: Theme.of(context).colorScheme.primary,
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320, // Maximum card width
                childAspectRatio: 0.65, // Width:Height ratio (2:3 poster with padding)
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: versions.length,
              itemBuilder: (context, index) {
                return VersionCard(
                  version: versions[index],
                  onTap: () => _navigateToSubversions(versions[index]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
