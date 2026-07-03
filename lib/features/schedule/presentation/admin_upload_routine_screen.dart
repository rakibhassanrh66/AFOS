import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/glass_card.dart';

class AdminUploadRoutineScreen extends StatefulWidget {
  const AdminUploadRoutineScreen({super.key});
  @override State<AdminUploadRoutineScreen> createState() => _AdminUploadState();
}

class _AdminUploadState extends State<AdminUploadRoutineScreen> {
  PlatformFile? _file;
  bool _uploading = false;
  String? _result, _error;
  String _mode = 'schedule'; // 'schedule' | 'transport'

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf', 'xlsx', 'xls']);
    if(res!=null) setState((){_file=res.files.first; _result=null; _error=null;});
  }

  Future<void> _upload() async {
    if(_file==null) return;
    setState((){_uploading=true; _result=null; _error=null;});
    try {
      final jwt = SupabaseConfig.jwt;
      final url = '${SupabaseConfig.url}/functions/v1/parse-routine';
      final formData = FormData.fromMap({
        'type': _mode,
        'file': await MultipartFile.fromFile(_file!.path!, filename:_file!.name),
      });
      final res = await Dio().post(url, data:formData,
        options:Options(headers:{'Authorization':'Bearer $jwt','apikey':SupabaseConfig.publishableKey}));
      final noun = _mode=='transport' ? 'transport routes' : 'class slots';
      setState(()=>_result='✅ ${res.data["slotsInserted"]} $noun loaded successfully! Students/teachers will see it live.');
    } catch(e) {
      final data = e is DioException ? e.response?.data : null;
      setState(()=>_error = data is Map && data['error']!=null ? data['error'].toString() : e.toString());
    } finally {
      if(mounted) setState(()=>_uploading=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AppBar(
        title: Text('Upload Schedule / Transport', style: TextStyle(color: textPrimary)),
        backgroundColor: AppColors.surfaceOf(context),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: Padding(
        padding:const EdgeInsets.all(24),
        child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
          RepaintBoundary(
            child: GlassCard(
              borderRadius: 20,
              glowColor: AppColors.holoBlue,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.upload_file_rounded, color: AppColors.holoBlue, size: 48)
                      .animate().scale(curve: Curves.easeOutCubic),
                  const SizedBox(height:16),
                  Text(_mode=='transport' ? 'Upload Transport Routes' : 'Upload Class Routine',
                      style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                  const SizedBox(height:8),
                  Text(_mode=='transport'
                      ? 'Admin uploads a PDF or Excel route sheet. The system auto-fills live transport routes for everyone.'
                      : 'Admin uploads a PDF or Excel timetable. The system auto-fills all student schedules.',
                      style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                ]),
              ),
            ),
          ),
          const SizedBox(height:16),
          Row(children:[
            Expanded(child: _ModeChip(
              label:'Class Schedule', selected:_mode=='schedule',
              onTap:()=>setState((){_mode='schedule'; _result=null; _error=null;}))),
            const SizedBox(width:10),
            Expanded(child: _ModeChip(
              label:'Transport Routes', selected:_mode=='transport',
              onTap:()=>setState((){_mode='transport'; _result=null; _error=null;}))),
          ]),
          const SizedBox(height:24),
          GestureDetector(
            onTap:_pickFile,
            child:Container(
              width:double.infinity, height:120,
              decoration:BoxDecoration(
                color:AppColors.glassFill(context), borderRadius:BorderRadius.circular(16),
                border:Border.all(color:_file!=null?AppColors.green:AppColors.glassBorder(context),
                  width: _file!=null?1.2:1,
                  style:BorderStyle.solid)),
              child:Center(child:_file==null
                ? Column(mainAxisSize:MainAxisSize.min,children:[
                    Icon(Icons.add_circle_outline,color:textSecondary,size:36),
                    const SizedBox(height:8),
                    Text('Tap to select PDF or Excel file',style:AppTextStyles.bodyMedium.copyWith(color:textSecondary)),
                  ])
                : Column(mainAxisSize:MainAxisSize.min,children:[
                    Icon(_file!.extension?.toLowerCase()=='pdf' ? Icons.picture_as_pdf : Icons.table_chart_rounded,
                        color: _file!.extension?.toLowerCase()=='pdf' ? AppColors.red : AppColors.green, size:36),
                    const SizedBox(height:8),
                    Text(_file!.name,style:AppTextStyles.titleMedium.copyWith(color:textPrimary)),
                    Text('${(_file!.size/1024).toStringAsFixed(1)} KB',
                        style:AppTextStyles.bodyMedium.copyWith(color:textSecondary)),
                  ])),
            ),
          ),
          const SizedBox(height:20),
          if(_file!=null) AfosButton(label:'Upload & Parse ${_mode=='transport'?'Routes':'Routine'}',loading:_uploading,onTap:_upload,
              color: AppColors.holoBlue),
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

class _ModeChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds:200), curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical:10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.holoBlue.withOpacity(0.15) : AppColors.glassFill(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.holoBlue : AppColors.glassBorder(context)),
        ),
        child: Text(label, style: AppTextStyles.bodyMedium.copyWith(
          color: selected ? AppColors.holoBlue : AppColors.textSecondaryOf(context),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }
}
