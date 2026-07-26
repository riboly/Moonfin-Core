import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../../../auth/repositories/user_repository.dart';
import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/item_mutation_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../navigation/home_refresh_bus.dart';
import '../add_to_collection_dialog.dart';
import '../add_to_playlist_dialog.dart';
import '../adaptive/adaptive_dialog.dart';
import '../change_artwork_dialog.dart';
import '../overlay_sheet.dart';

class ItemContextAction {
  final IconData icon;
  final String label;
  final Future<void> Function() onSelect;

  const ItemContextAction({
    required this.icon,
    required this.label,
    required this.onSelect,
  });
}

List<ItemContextAction> contextActionsFor(
  BuildContext context,
  AggregatedItem item, {
  VoidCallback? onChanged,
}) {
  final l10n = AppLocalizations.of(context);
  final mutations = GetIt.instance<ItemMutationRepository>();
  final client = GetIt.instance<MediaServerClient>();
  final currentUser = GetIt.instance<UserRepository>().currentUser;
  final isAdminUser = currentUser?.isAdministrator ?? false;
  final isSameServerItem = currentUser?.serverId == item.serverId;
  final requiresCollectionPermission =
      client.serverType == ServerType.jellyfin && isSameServerItem;
  final canManageCollections =
      !requiresCollectionPermission ||
      currentUser?.canManageCollections == true ||
      isAdminUser;
  final canRefreshMetadata =
      client.serverType == ServerType.jellyfin && isAdminUser;
  final actions = <ItemContextAction>[];
  final type = item.type;

  final isMediaType =
      type == 'Movie' ||
      type == 'Episode' ||
      type == 'Series' ||
      type == 'Season' ||
      type == 'Audio' ||
      type == 'MusicAlbum' ||
      type == 'BoxSet';

  if (isMediaType) {
    actions.add(ItemContextAction(
      icon: item.isPlayed
          ? Icons.visibility_off_outlined
          : Icons.visibility_outlined,
      label: item.isPlayed
          ? l10n.contextMenuMarkUnwatched
          : l10n.contextMenuMarkWatched,
      onSelect: () async {
        await mutations.setPlayed(item.id, isPlayed: !item.isPlayed);
        onChanged?.call();
      },
    ));

    final hasProgress = item.playbackPositionTicks != null &&
        item.playbackPositionTicks! > 0 &&
        !item.isPlayed;
    if (hasProgress) {
      actions.add(ItemContextAction(
        icon: Icons.visibility_off_outlined,
        label: l10n.contextMenuHideFromContinueWatching,
        onSelect: () async {
          final prefs = GetIt.instance<UserPreferences>();
          if (item.seriesId != null && item.seriesId!.isNotEmpty) {
            await prefs.hideFromContinueWatching(item.seriesId!);
          } else {
            await prefs.hideFromContinueWatching(item.id);
          }
          try {
            await client.userLibraryApi.unmarkPlayed(item.id);
          } catch (_) {}
          onChanged?.call();
        },
      ));
    }

    final isEpisode = type == 'Episode';
    final hasSeries = item.seriesId != null && item.seriesId!.isNotEmpty;
    if (isEpisode && hasSeries) {
      actions.add(ItemContextAction(
        icon: Icons.visibility_off_outlined,
        label: l10n.contextMenuHideFromNextUp,
        onSelect: () async {
          final prefs = GetIt.instance<UserPreferences>();
          await prefs.hideFromNextUp(item.seriesId!);
          await prefs.hideFromContinueWatching(item.seriesId!);
          try {
            await client.userLibraryApi.unmarkPlayed(item.id);
          } catch (_) {}
          onChanged?.call();
        },
      ));
    }

    actions.add(ItemContextAction(
      icon: item.isFavorite ? Icons.favorite : Icons.favorite_border,
      label: item.isFavorite
          ? l10n.contextMenuRemoveFromFavorites
          : l10n.contextMenuAddToFavorites,
      onSelect: () async {
        await mutations.setFavorite(item.id, isFavorite: !item.isFavorite);
        onChanged?.call();
      },
    ));

    if (canManageCollections) {
      actions.add(ItemContextAction(
        icon: Icons.collections_bookmark,
        label: l10n.contextMenuAddToCollection,
        onSelect: () async {
          if (!context.mounted) return;
          final added = await AddToCollectionDialog.show(
            context,
            itemIds: [item.id],
            serverId: item.serverId,
          );
          if (added == true) {
            onChanged?.call();
          }
        },
      ));
    }

    actions.add(ItemContextAction(
      icon: Icons.playlist_add,
      label: l10n.addToPlaylist,
      onSelect: () async {
        if (!context.mounted) return;
        final added = await AddToPlaylistDialog.show(
          context,
          itemIds: [item.id],
          serverId: item.serverId,
        );
        if (added == true) {
          onChanged?.call();
        }
      },
    ));

    if (canRefreshMetadata) {
      actions.add(ItemContextAction(
        icon: Icons.refresh,
        label: l10n.adminRefreshMetadata,
        onSelect: () async {
          try {
            await mutations.refreshMetadata(item.id);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.adminMetadataRefreshRequested)),
            );
            onChanged?.call();
          } on DioException catch (e) {
            final status = e.response?.statusCode;
            final data = e.response?.data;
            final serverMessage = data is String
                ? data
                : (data is Map<String, dynamic>
                      ? (data['message'] ?? data['Message'])?.toString()
                      : null);
            final fallback = switch (status) {
              401 => 'Unauthorized',
              403 => 'Forbidden',
              404 => 'Not found',
              _ => 'HTTP ${status ?? 'error'}',
            };
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  l10n.adminMetadataRefreshFailed(
                    (serverMessage != null && serverMessage.isNotEmpty)
                        ? serverMessage
                        : fallback,
                  ),
                ),
              ),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.adminMetadataRefreshFailed('$e'))),
            );
          }
        },
      ));
    }

    // Windows: Emby/Jellyfin server-side delete (uses server CanDelete flag).
    if (PlatformDetection.isWindows && item.canDelete) {
      actions.add(ItemContextAction(
        icon: Icons.delete_forever,
        label: l10n.deleteItem,
        onSelect: () async {
          if (!context.mounted) return;
          final confirmed = await showFocusRestoringDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog.adaptive(
              backgroundColor: const Color(0xFF171717),
              title: Text(
                l10n.deleteItem,
                style: const TextStyle(color: Colors.white),
              ),
              content: Text(
                l10n.deleteConfirmMessage(item.name),
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                adaptiveDialogAction(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.cancel),
                ),
                adaptiveDialogAction(
                  onPressed: () => Navigator.pop(ctx, true),
                  isDestructive: true,
                  child: Text(
                    l10n.delete,
                    style: const TextStyle(color: Color(0xFFD32F2F)),
                  ),
                ),
              ],
            ),
          );
          if (confirmed != true) return;

          try {
            await client.itemsApi.deleteItem(item.id);
            homeRefreshBus.requestNowOrAfterNavigation();
            onChanged?.call();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.itemDeleted)),
            );
          } on DioException catch (e) {
            final status = e.response?.statusCode;
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  (status == 401 || status == 403)
                      ? l10n.requestErrorPermission
                      : l10n.failedToDeleteItemWithError(
                          e.response?.statusMessage ?? e.message ?? '$e',
                        ),
                ),
                backgroundColor: const Color(0xFFD32F2F),
              ),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.failedToDeleteItemWithError('$e')),
                backgroundColor: const Color(0xFFD32F2F),
              ),
            );
          }
        },
      ));
    }

  }

  final canChangeArtwork = (isMediaType ||
          type == 'Folder' ||
          type == 'CollectionFolder' ||
          type == 'UserView' ||
          type == 'Genre' ||
          type == 'MusicGenre') &&
      client.serverType == ServerType.jellyfin &&
      isAdminUser;

  if (canChangeArtwork) {
    actions.add(ItemContextAction(
      icon: Icons.image_outlined,
      label: l10n.changeArtwork,
      onSelect: () async {
        if (!context.mounted) return;
        final changed = await ChangeArtworkDialog.show(
          context,
          item: item,
        );
        if (changed == true) {
          onChanged?.call();
        }
      },
    ));
  }

  if (type == 'Episode' && (item.seriesId?.isNotEmpty ?? false)) {
    actions.add(ItemContextAction(
      icon: Icons.tv_outlined,
      label: l10n.contextMenuGoToSeries,
      onSelect: () async {
        if (!context.mounted) return;
        context.push(Destinations.item(item.seriesId!, serverId: item.serverId));
      },
    ));
  }

  return actions;
}
