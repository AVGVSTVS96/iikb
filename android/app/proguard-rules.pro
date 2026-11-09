# Swift calls these by name through JNI.
-keep class com.shahidy.iikb.keyboard.Field { *; }
-keep class com.shahidy.iikb.keyboard.Native { *; }
# sherpa-onnx reads its configs and results by field name through JNI.
-keep class com.k2fsa.sherpa.onnx.** { *; }
