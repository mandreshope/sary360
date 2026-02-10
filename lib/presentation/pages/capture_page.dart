import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera_360/camera_360.dart';

import '../../core/constants/app_constants.dart';
import '../viewmodels/capture_viewmodel.dart';
import 'viewer_page.dart';

class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key});

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = ref.watch(captureViewModelProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody(context, viewModel)),
    );
  }

  Widget _buildBody(BuildContext context, CaptureViewState viewModel) {
    // Gestion des différents états
    switch (viewModel.state) {
      case CaptureState.completed:
        // Naviguer automatiquement vers le viewer
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (viewModel.completedPanorama != null) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    ViewerPage(panorama: viewModel.completedPanorama!),
              ),
            );
          }
        });
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );

      case CaptureState.error:
        return _buildErrorView(context, viewModel);

      default:
        return _buildCaptureView(context);
    }
  }

  Widget _buildCaptureView(BuildContext context) {
    return Camera360(
      userNrPhotos: AppConstants.numberOfPhotos,
      userCapturedImageWidth: AppConstants.maxImageWidth,
      userCapturedImageQuality: AppConstants.jpegQuality,
      onCaptureEnded: (data) {
        ref.read(captureViewModelProvider.notifier).handleCaptureResult(data);
      },
      onCaptureCancelled: () {
        Navigator.of(context).pop();
      },
    );
  }

  Widget _buildErrorView(BuildContext context, CaptureViewState viewModel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 24),
            const Text(
              'Erreur',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.errorMessage ?? 'Une erreur est survenue',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(captureViewModelProvider.notifier).reset();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
