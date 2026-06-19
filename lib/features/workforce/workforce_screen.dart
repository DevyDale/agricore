import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/data_list.dart';
import '../../widgets/entity_tile.dart';

class WorkforceScreen extends StatelessWidget {
  const WorkforceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiService(context.read<DioClient>().dio);
    return DataList(
      loader: () => api.list(Api.jobPostings),
      emptyText: 'No job postings available.',
      itemBuilder: (context, j) {
        final title = pickString(j, ['title', 'role', 'name']) ?? 'Job posting';
        final desc = pickString(j, ['description', 'summary', 'details']);
        return EntityTile(
          icon: Icons.work_outline_rounded,
          tone: 'plum',
          title: title,
          subtitle: desc,
        );
      },
    );
  }
}
