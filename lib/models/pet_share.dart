/// How a pet is shared with the family through sixsevenweb.com: everyone
/// with [code] sees and changes the same pet.
class PetShare {
  const PetShare({
    required this.code,
    required this.version,
    this.ownerKey,
    this.dirty = false,
    this.photoUrl,
    this.uploadedPhotoPath,
    this.caregiverId,
  });

  /// "K7Q2M9XP", what the family types to join.
  final String code;

  /// Server version this phone's copy is based on.
  final int version;

  /// Only on the phone that shared it: lets it stop sharing.
  final String? ownerKey;

  /// Changed here and not sent yet.
  final bool dirty;

  /// The photo on the server this phone already has.
  final String? photoUrl;

  /// The local photo already sent to the server.
  final String? uploadedPhotoPath;

  /// Only on a caregiver's phone: which of the pet's caregivers it is (see
  /// Caregiver). The pet leaves this phone when that care ends.
  final String? caregiverId;

  bool get isOwner => ownerKey != null;

  bool get isCaregiver => caregiverId != null;

  /// "K7Q2-M9XP", easier to read and dictate.
  String get displayCode =>
      code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

  PetShare copyWith({
    int? version,
    bool? dirty,
    String? photoUrl,
    String? uploadedPhotoPath,
  }) =>
      PetShare(
        code: code,
        version: version ?? this.version,
        ownerKey: ownerKey,
        dirty: dirty ?? this.dirty,
        photoUrl: photoUrl ?? this.photoUrl,
        uploadedPhotoPath: uploadedPhotoPath ?? this.uploadedPhotoPath,
        caregiverId: caregiverId,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'version': version,
        'ownerKey': ownerKey,
        'dirty': dirty,
        'photoUrl': photoUrl,
        'uploadedPhotoPath': uploadedPhotoPath,
        if (caregiverId != null) 'caregiverId': caregiverId,
      };

  factory PetShare.fromJson(Map<String, dynamic> json) => PetShare(
        code: json['code'] as String,
        version: json['version'] as int? ?? 1,
        ownerKey: json['ownerKey'] as String?,
        dirty: json['dirty'] as bool? ?? false,
        photoUrl: json['photoUrl'] as String?,
        uploadedPhotoPath: json['uploadedPhotoPath'] as String?,
        caregiverId: json['caregiverId'] as String?,
      );
}
