import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';

class RentalApplicationPage extends StatefulWidget {
  const RentalApplicationPage({super.key});

  @override
  State<RentalApplicationPage> createState() => _RentalApplicationPageState();
}

class _RentalApplicationPageState extends State<RentalApplicationPage> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _businessAddressController = TextEditingController();

  String _status = 'pending';
  String? _adminNotes;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchApplicationStatus();
  }

  /// Ambil status pengajuan dari backend Laravel
  Future<void> _fetchApplicationStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');

      if (token == null) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/rental-application'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final appData = data['data'];

        if (appData != null) {
          setState(() {
            _businessNameController.text = appData['business_name'] ?? '';
            _businessAddressController.text = appData['business_address'] ?? '';
            _status = appData['status'] ?? 'pending';
            _adminNotes = appData['admin_notes'];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetch application: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Kirim / Update Pengajuan ke Backend API
  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/rental-application'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'business_name': _businessNameController.text,
          'business_address': _businessAddressController.text,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Pengajuan perental berhasil dikirim!")),
          );
        }
        _fetchApplicationStatus(); // Refresh status
      } else {
        String errorMessage = responseData['message'] ?? 'Gagal mengirim pengajuan';
        if (responseData['errors'] != null && responseData['errors']['personal_data'] != null) {
          errorMessage = responseData['errors']['personal_data'][0];
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengajuan Perental'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner Status Pengajuan
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _status == 'approved' 
                            ? Colors.green.shade50 
                            : _status == 'rejected' 
                                ? Colors.red.shade50 
                                : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _status == 'approved' 
                              ? Colors.green 
                              : _status == 'rejected' 
                                  ? Colors.red 
                                  : Colors.orange,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _status == 'approved' 
                                    ? Icons.check_circle 
                                    : _status == 'rejected' 
                                        ? Icons.cancel 
                                        : Icons.hourglass_top,
                                color: _status == 'approved' 
                                    ? Colors.green 
                                    : _status == 'rejected' 
                                        ? Colors.red 
                                        : Colors.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "Status: ${_status.toUpperCase()}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _status == 'approved'
                                ? "Selamat! Pengajuan Anda telah disetujui sebagai perental."
                                : _status == 'rejected'
                                    ? "Pengajuan Anda ditolak oleh admin."
                                    : "Pengajuan Anda sedang ditinjau oleh Admin.",
                            style: const TextStyle(fontSize: 13),
                          ),
                          
                          // Catatan Admin (Tampil otomatis kapanpun ada isinya, tidak harus rejected)
                          if (_adminNotes != null && _adminNotes!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Catatan dari Admin:",
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _adminNotes!,
                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Informasi Peringatan Persyaratan
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Pastikan Anda sudah melengkapi Foto KTP dan Foto SIM di menu Profil sebelum mengirim pengajuan ini.",
                              style: TextStyle(fontSize: 12, color: Colors.blueAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Form Input Data Usaha
                    TextFormField(
                      controller: _businessNameController,
                      decoration: const InputDecoration(
                        labelText: "Nama Usaha Rental (Opsional)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.store),
                      ),
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                      controller: _businessAddressController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Alamat Usaha / Domisili",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      validator: (v) => v == null || v.isEmpty ? "Alamat usaha wajib diisi" : null,
                    ),
                    const SizedBox(height: 30),

                    // Tombol Submit
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue, 
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isSubmitting ? null : _submitApplication,
                        child: _isSubmitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("Kirim / Perbarui Pengajuan", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}