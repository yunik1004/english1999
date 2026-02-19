import 'package:web/web.dart' as web;

void setWebDraggingState(bool isDragging) {
  final body = web.document.body;
  if (body != null) {
    if (isDragging) {
      body.classList.add('flutter-dragging');
    } else {
      body.classList.remove('flutter-dragging');
    }
  }
}
