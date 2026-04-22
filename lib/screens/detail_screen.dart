import 'package:flutter/material.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/media_item.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      appBar: AppBar(title: Text(mediaItem.title)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              mediaItem.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.typeEmphasis,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            Text(
              mediaItem.overview.isEmpty
                  ? 'No overview available.'
                  : mediaItem.overview,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
