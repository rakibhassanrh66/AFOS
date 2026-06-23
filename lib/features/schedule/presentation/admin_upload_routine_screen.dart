import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/afos_button.dart';

class AdminUploadRoutineScreen extends StatefulWidget {
  const AdminUploadRoutineScreen({super.key});
  @override State<AdminUploadRoutineScreen> createState() => _AdminUploadState();
}

class _AdminUploadState extends State<AdminUploadRoutineScreen> {
  PlatformFile? _file;
  bool _uploading = false;
  String? _result, _error;

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['pdf']);
    if(res!=null) setState(()=>_file=res.files.first);
  }

  Future<void> _upload() async {
    if(_file==null) return;
    setState(()=>_uploading=true);
    try {
      final jwt = SupabaseConfig.jwt;
      final url = '${SupabaseConfig.url}/functions/v1/parse-routine';
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(_file!.path!, filename:_file!.name),
      });
      final res = await Dio().post(url, data:formData,
        options:Options(headers:{'Authorization':'Bearer $jwt','apikey':SupabaseConfig.anonKey}));
      setState(()=>_result='✅ ${res.data["slotsInserted"]} class slots loaded successfully!');
    } catch(e) {
      setState(()=>_error=e.toString());
    } finally {
      if(mounted) setState(()=>_uploading=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title:const Text('Upload Routine PDF'),backgroundColor:AppColors.surface),
      body: Padding(
        padding:const EdgeInsets.all(24),
        child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
          const Icon(Icons.upload_file_rounded,color:AppColors.blue,size:48).animate().scale(),
          const SizedBox(height:16),
          Text('Upload Class Routine',style:AppTextStyles.headlineLarge),
          const SizedBox(height:8),
          Text('Admin uploads a PDF timetable. The system auto-fills all student schedules.',
            style:AppTextStyles.bodyMedium),
          const SizedBox(height:32),
          GestureDetector(
            onTap:_pickFile,
            child:Container(
              width:double.infinity, height:120,
              decoration:BoxDecoration(
                color:AppColors.card, borderRadius:BorderRadius.circular(16),
                border:Border.all(color:_file!=null?AppColors.green:AppColors.border,
                  style:BorderStyle.solid)),
              child:Center(child:_file==null
                ? Column(mainAxisSize:MainAxisSize.min,children:[
                    const Icon(Icons.add_circle_outline,color:AppColors.textSecondary,size:36),
                    const SizedBox(height:8),
                    Text('Tap to select PDF',style:AppTextStyles.bodyMedium),
                  ])
                : Column(mainAxisSize:MainAxisSize.min,children:[
                    const Icon(Icons.picture_as_pdf,color:AppColors.red,size:36),
                    const SizedBox(height:8),
                    Text(_file!.name,style:AppTextStyles.titleMedium),
                    Text('${(_file!.size/1024).toStringAsFixed(1)} KB',style:AppTextStyles.bodyMedium),
                  ])),
            ),
          ),
          const SizedBox(height:20),
          if(_file!=null) AfosButton(label:'Upload & Parse Routine',loading:_uploading,onTap:_upload),
          if(_result!=null) Padding(padding:const EdgeInsets.only(top:16),
            child:Container(padding:const EdgeInsets.all(14),
              decoration:BoxDecoration(color:AppColors.green.withOpacity(0.1),borderRadius:BorderRadius.circular(10),
                border:Border.all(color:AppColors.green.withOpacity(0.3))),
              child:Text(_result!,style:const TextStyle(color:AppColors.green,fontWeight:FontWeight.w600)))),
          if(_error!=null) Padding(padding:const EdgeInsets.only(top:16),
            child:Container(padding:const EdgeInsets.all(14),
              decoration:BoxDecoration(color:AppColors.red.withOpacity(0.1),borderRadius:BorderRadius.circular(10),
                border:Border.all(color:AppColors.red.withOpacity(0.3))),
              child:Text(_error!,style:const TextStyle(color:AppColors.red)))),
        ]),
      ),
    );
  }
}
