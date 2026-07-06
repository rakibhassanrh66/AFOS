import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/supernova_loader.dart';

class AdminUploadRoutineScreen extends StatefulWidget {
  const AdminUploadRoutineScreen({super.key});
  @override State<AdminUploadRoutineScreen> createState() => _AdminUploadState();
}

class _AdminUploadState extends State<AdminUploadRoutineScreen> {
  PlatformFile? _file;
  bool _uploading = false;
  String? _result, _error;
  String _mode = 'class_routine'; // 'class_routine' | 'exam_routine' | 'transport' | 'schedule'

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf', 'xlsx', 'xls']);
    if(res!=null) setState((){_file=res.files.first; _result=null; _error=null;});
  }

  /// PDFs are parsed to text lines right here on-device (Syncfusion's PDF
  /// text extractor), not on the server — a multi-page routine PDF has
  /// thousands of positioned text runs, which reliably blew past the edge
  /// function's CPU/time budget and crashed it (HTTP 546). The phone has
  /// no such limit, so only the already-extracted, tiny text payload goes
  /// to the server for the lightweight regex parsing.
  List<String> _extractPdfLines(String path) {
    final bytes = File(path).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final textLines = PdfTextExtractor(doc).extractTextLines();
      return textLines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList();
    } finally {
      doc.dispose();
    }
  }

  Future<void> _upload() async {
    if(_file==null) return;
    setState((){_uploading=true; _result=null; _error=null;});
    try {
      final jwt = SupabaseConfig.jwt;
      final url = '${SupabaseConfig.url}/functions/v1/parse-routine';
      final isPdf = _file!.extension?.toLowerCase() == 'pdf';
      final headers = {'Authorization':'Bearer $jwt','apikey':SupabaseConfig.publishableKey};

      final Response res;
      if (isPdf) {
        final lines = _extractPdfLines(_file!.path!);
        if (lines.isEmpty) {
          throw 'Could not read any text from this PDF — it may be a scanned image rather than a text PDF.';
        }
        res = await Dio().post(url,
            data: {'type': _mode, 'lines': lines},
            options: Options(headers: {...headers, 'Content-Type': 'application/json'}));
      } else {
        final formData = FormData.fromMap({
          'type': _mode,
          'file': await MultipartFile.fromFile(_file!.path!, filename:_file!.name),
        });
        res = await Dio().post(url, data:formData, options:Options(headers:headers));
      }

      final noun = switch (_mode) {
        'transport' => 'transport routes',
        'exam_routine' => 'exam entries',
        _ => 'class slots',
      };
      final removed = res.data["slotsRemoved"] ?? 0;
      final removedNote = removed > 0 ? ' $removed obsolete $noun cleared.' : '';
      setState(()=>_result='✅ ${res.data["slotsInserted"]} $noun loaded successfully!$removedNote Students/teachers will see it live.');
    } catch(e) {
      final data = e is DioException ? e.response?.data : null;
      setState(()=>_error = data is Map && data['error']!=null ? data['error'].toString() : friendlyError(e));
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
      body: SingleChildScrollView(
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
                  Text(switch (_mode) {
                        'transport' => 'Upload Transport Routes',
                        'exam_routine' => 'Upload Exam Routine',
                        _ => 'Upload Class Routine',
                      },
                      style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                  const SizedBox(height:8),
                  Text(switch (_mode) {
                        'transport' => 'Admin uploads a PDF or Excel route sheet, in whatever layout the transport office exports — merged cells, multi-row stop times, or a flat table all work. Live routes update for everyone instantly.',
                        'exam_routine' => 'Admin uploads a mid/final term exam routine PDF or Excel (like the Examination Committee routine). The system reads date, slot time, course, and batch, and shows each student/teacher only their own relevant exams.',
                        _ => 'Admin uploads a class routine PDF or Excel — room x day x time grid, batch/section per class. The system reads it and shows each student/teacher only their own classes.',
                      },
                      style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                ]),
              ),
            ),
          ),
          const SizedBox(height:16),
          Row(children:[
            Expanded(child: _ModeChip(
              label:'Class Routine', selected:_mode=='class_routine',
              onTap:()=>setState((){_mode='class_routine'; _result=null; _error=null;}))),
            const SizedBox(width:10),
            Expanded(child: _ModeChip(
              label:'Exam Routine', selected:_mode=='exam_routine',
              onTap:()=>setState((){_mode='exam_routine'; _result=null; _error=null;}))),
          ]),
          const SizedBox(height:10),
          Row(children:[
            Expanded(child: _ModeChip(
              label:'Transport Routes', selected:_mode=='transport',
              onTap:()=>setState((){_mode='transport'; _result=null; _error=null;}))),
            const SizedBox(width:10),
            Expanded(child: _ModeChip(
              label:'Legacy Schedule', selected:_mode=='schedule',
              onTap:()=>setState((){_mode='schedule'; _result=null; _error=null;}))),
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
          if(_uploading) Padding(padding: const EdgeInsets.only(top: 28),
              child: Center(child: SupernovaBusy(
                  label: _file!.extension?.toLowerCase() == 'pdf'
                      ? 'Reading the PDF and matching rooms, teachers and times…'
                      : 'Reading the sheet and matching routes…'))),
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
