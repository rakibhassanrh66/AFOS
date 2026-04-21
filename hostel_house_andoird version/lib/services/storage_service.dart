import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadImage(File imageFile, String path) async {
    try {
      Reference ref = _storage.ref().child(path);
      UploadTask uploadTask = ref.putFile(imageFile);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  Future<void> deleteImage(String imageUrl) async {
    try {
      Reference ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      // Image might not exist, ignore error
    }
  }

  Future<List<String>> uploadImages(List<File> imageFiles, String folder) async {
    List<String> urls = [];
    for (int i = 0; i < imageFiles.length; i++) {
      String path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      String url = await uploadImage(imageFiles[i], path);
      urls.add(url);
    }
    return urls;
  }
}