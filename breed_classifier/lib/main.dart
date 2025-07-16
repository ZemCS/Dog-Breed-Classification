import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const DogBreedPredictorApp());
}

class DogBreedPredictorApp extends StatelessWidget {
  const DogBreedPredictorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dog Breed Predictor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const DogBreedPredictorScreen(),
    );
  }
}

class DogBreedPredictorScreen extends StatefulWidget {
  const DogBreedPredictorScreen({super.key});

  @override
  _DogBreedPredictorScreenState createState() => _DogBreedPredictorScreenState();
}

class _DogBreedPredictorScreenState extends State<DogBreedPredictorScreen> {
  File? _image;
  List<Map<String, dynamic>> _predictions = [];
  bool _isLoading = false;
  String _errorMessage = '';
  bool _showConfidences = false;
  String _feedbackMessage = '';

  final ImagePicker _picker = ImagePicker();
  final String apiUrl = 'http://192.168.18.132:5000'; // Update with your API URL

  Future<File> _fixImageOrientation(File imageFile) async {
    // Read the image
    final imageBytes = await imageFile.readAsBytes();
    img.Image? image = img.decodeImage(imageBytes);

    if (image == null) return imageFile;

    // Fix orientation (rotates/flips based on EXIF data)
    image = img.bakeOrientation(image);

    // Save the corrected image to a temporary file
    final tempDir = await getTemporaryDirectory();
    final correctedImagePath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final correctedImageFile = File(correctedImagePath);
    await correctedImageFile.writeAsBytes(img.encodeJpg(image));

    return correctedImageFile;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        File correctedImage = await _fixImageOrientation(File(pickedFile.path));
        setState(() {
          _image = correctedImage;
          _predictions = [];
          _errorMessage = '';
          _showConfidences = false;
          _feedbackMessage = '';
        });
        await _predictBreed();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking image: $e';
      });
    }
  }

  Future<void> _predictBreed() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _feedbackMessage = '';
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiUrl/predict'));
      request.files.add(await http.MultipartFile.fromPath('image', _image!.path));
      
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode == 200 && jsonResponse['status'] == 'success') {
        setState(() {
          _predictions = List<Map<String, dynamic>>.from(jsonResponse['predictions']);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = jsonResponse['error'] ?? 'Failed to get predictions';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error connecting to API: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _submitFeedback(String correctBreed) async {
    if (_image == null || _predictions.isEmpty) return;

    setState(() {
      _isLoading = true;
      _feedbackMessage = '';
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiUrl/feedback'));
      request.files.add(await http.MultipartFile.fromPath('image', _image!.path));
      request.fields['correct_breed'] = correctBreed;
      request.fields['original_top_breed'] = _predictions[0]['breed'];

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode == 200 && jsonResponse['status'] == 'success') {
        setState(() {
          _feedbackMessage = jsonResponse['message'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _feedbackMessage = jsonResponse['error'] ?? 'Failed to submit feedback';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _feedbackMessage = 'Error submitting feedback: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dog Breed Predictor'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () => _pickImage(ImageSource.camera),
                child: const Text('Take Photo'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _pickImage(ImageSource.gallery),
                child: const Text('Pick from Gallery'),
              ),
              const SizedBox(height: 16),
              if (_image != null)
                Container(
                  constraints: BoxConstraints(
                    maxHeight: 200,
                    maxWidth: MediaQuery.of(context).size.width - 32,
                  ),
                  child: Image.file(
                    _image!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Text('Error loading image preview');
                    },
                  ),
                ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator()),
              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              if (_feedbackMessage.isNotEmpty)
                Text(
                  _feedbackMessage,
                  style: const TextStyle(color: Colors.green),
                  textAlign: TextAlign.center,
                ),
              if (_predictions.isNotEmpty && !_showConfidences) ...[
                const Text(
                  'Predicted Breed:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: Text(_predictions[0]['breed']),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showConfidences = true;
                    });
                  },
                  child: const Text('Show Confidence'),
                ),
              ],
              if (_predictions.isNotEmpty && _showConfidences) ...[
                const Text(
                  'Top Predictions (Click to Submit Correct Breed):',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._predictions.map((prediction) => Card(
                      child: ListTile(
                        title: Text(prediction['breed']),
                        subtitle: Text(
                            '${prediction['confidence'].toStringAsFixed(2)}%'),
                        onTap: () => _submitFeedback(prediction['breed']),
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}