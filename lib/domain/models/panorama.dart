import 'dart:io';

/// Classe représentant un panorama capturé
class Panorama {
  final String id;
  final String name;
  final DateTime createdAt;
  final String stitchedImagePath;
  final List<String> originalPhotoPaths;
  final int photoCount;

  const Panorama({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.stitchedImagePath,
    required this.originalPhotoPaths,
    required this.photoCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'stitchedImagePath': stitchedImagePath,
    'originalPhotoPaths': originalPhotoPaths,
    'photoCount': photoCount,
  };

  factory Panorama.fromJson(Map<String, dynamic> json) => Panorama(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    stitchedImagePath: json['stitchedImagePath'] as String,
    originalPhotoPaths: (json['originalPhotoPaths'] as List).cast<String>(),
    photoCount: json['photoCount'] as int,
  );

  Panorama copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    String? stitchedImagePath,
    List<String>? originalPhotoPaths,
    int? photoCount,
  }) {
    return Panorama(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      stitchedImagePath: stitchedImagePath ?? this.stitchedImagePath,
      originalPhotoPaths: originalPhotoPaths ?? this.originalPhotoPaths,
      photoCount: photoCount ?? this.photoCount,
    );
  }

  bool get exists => File(stitchedImagePath).existsSync();
}
