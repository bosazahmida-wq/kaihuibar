enum MeetingMode { moderated, free, manual }

extension MeetingModeLabel on MeetingMode {
  String get label {
    switch (this) {
      case MeetingMode.moderated:
        return '主持编排';
      case MeetingMode.free:
        return '自由辩论';
      case MeetingMode.manual:
        return '手动点名';
    }
  }
}

String meetingModeText(String mode) {
  switch (mode) {
    case 'moderated':
      return '主持编排';
    case 'free':
      return '自由辩论';
    case 'manual':
      return '手动点名';
    default:
      return mode;
  }
}

String meetingStatusText(String status) {
  switch (status) {
    case 'created':
      return '已创建';
    case 'running':
      return '进行中';
    case 'completed':
      return '已完成';
    default:
      return status;
  }
}

String friendshipStatusText(String status) {
  switch (status) {
    case 'pending':
      return '待处理';
    case 'accepted':
      return '已通过';
    case 'blocked':
      return '已屏蔽';
    default:
      return status;
  }
}

String friendshipDirectionText(String direction) {
  switch (direction) {
    case 'incoming':
      return '收到申请';
    case 'outgoing':
      return '我发起的';
    case 'connected':
      return '已建立关系';
    default:
      return '关系';
  }
}

class MeetingParticipantInput {
  MeetingParticipantInput({
    required this.participantType,
    required this.participantId,
    required this.role,
  });

  final String participantType;
  final String participantId;
  final String role;

  Map<String, dynamic> toJson() => {
        'participant_type': participantType,
        'participant_id': participantId,
        'role': role,
      };
}
