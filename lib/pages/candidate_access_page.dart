import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/api_client.dart';

class CandidateAccessPage extends ConsumerStatefulWidget {
  const CandidateAccessPage({super.key});

  @override
  ConsumerState<CandidateAccessPage> createState() =>
      _CandidateAccessPageState();
}

class _CandidateAccessPageState extends ConsumerState<CandidateAccessPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _fecCandidateController = TextEditingController();
  final _fecCommitteeController = TextEditingController();
  final _stateController = TextEditingController();
  final _countyController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();

  String _level = 'federal';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _addressController.dispose();
    _fecCandidateController.dispose();
    _fecCommitteeController.dispose();
    _stateController.dispose();
    _countyController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    setState(() {
      _isSubmitting = true;
    });
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.createCandidateApplication(
        fullName: _fullNameController.text.trim(),
        campaignAddress: _addressController.text.trim(),
        fecCandidateId: _fecCandidateController.text.trim(),
        fecCommitteeId: _fecCommitteeController.text.trim(),
        level: _level,
        state: _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        county: _countyController.text.trim().isEmpty
            ? null
            : _countyController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        district: _districtController.text.trim().isEmpty
            ? null
            : _districtController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Application submitted. Status: pending'),
          ),
        );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Submit failed: ${error.message}')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Submit failed: $error')),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apply for candidate access'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Campaign & filing details',
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullNameController,
                  decoration:
                      const InputDecoration(labelText: 'Full legal name'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Registered campaign address',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fecCandidateController,
                  decoration:
                      const InputDecoration(labelText: 'FEC candidate number'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fecCommitteeController,
                  decoration:
                      const InputDecoration(labelText: 'FEC committee number'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _level,
                  decoration:
                      const InputDecoration(labelText: 'Government level'),
                  items: const [
                    DropdownMenuItem(
                      value: 'federal',
                      child: Text('Federal'),
                    ),
                    DropdownMenuItem(
                      value: 'state',
                      child: Text('State'),
                    ),
                    DropdownMenuItem(
                      value: 'county',
                      child: Text('County'),
                    ),
                    DropdownMenuItem(
                      value: 'city',
                      child: Text('City'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _level = value ?? 'federal';
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _stateController,
                  decoration: const InputDecoration(
                    labelText: 'State (e.g., MT)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _countyController,
                  decoration: const InputDecoration(
                    labelText: 'County',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'City',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _districtController,
                  decoration: const InputDecoration(
                    labelText: 'District number',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit application'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
