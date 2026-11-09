# Swift calls these by name through JNI.
-keep class com.shahidy.iikb.keyboard.Field { *; }
-keep class com.shahidy.iikb.keyboard.Native { *; }
-keep class com.shahidy.iikb.app.PreviewField { *; }
-keep class com.shahidy.iikb.app.Core { *; }
# sherpa-onnx reads its configs and results by field name through JNI.
-keep class com.k2fsa.sherpa.onnx.** { *; }
