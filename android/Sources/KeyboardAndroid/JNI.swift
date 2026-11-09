import CJNI

/// The JNI environment of the thread a call from Kotlin arrived on. Strings cross as UTF-8 byte arrays both ways, since
/// JNI's own strings are modified UTF-8, which spells an emoji as two surrogates.
public typealias Env = UnsafeMutablePointer<JNIEnv?>

extension UnsafeMutablePointer where Pointee == JNIEnv? {
    var jni: JNINativeInterface { pointee!.pointee }

    func bytes(_ array: jbyteArray?) -> [UInt8] {
        guard let array else { return [] }
        let count = Int(jni.GetArrayLength(self, array))
        return [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            jni.GetByteArrayRegion(
                self, array, 0, jsize(count),
                UnsafeMutableRawPointer(buffer.baseAddress)?
                    .assumingMemoryBound(to: jbyte.self))
            initialized = count
        }
    }

    func string(_ array: jbyteArray?) -> String? {
        array.map { String(decoding: bytes($0), as: UTF8.self) }
    }

    func array(_ bytes: some Collection<UInt8>) -> jbyteArray? {
        let array = jni.NewByteArray(self, jsize(bytes.count))
        Array(bytes).withUnsafeBufferPointer { buffer in
            jni.SetByteArrayRegion(
                self, array, 0, jsize(buffer.count),
                UnsafeRawPointer(buffer.baseAddress)?.assumingMemoryBound(to: jbyte.self))
        }
        return array
    }

    func array(_ text: String) -> jbyteArray? { array(text.utf8) }

    func floats(_ array: jfloatArray?) -> [Float] {
        guard let array else { return [] }
        let count = Int(jni.GetArrayLength(self, array))
        return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            jni.GetFloatArrayRegion(self, array, 0, jsize(count), buffer.baseAddress)
            initialized = count
        }
    }

    /// A direct buffer's memory, read in place: Kotlin keeps the mapped file alive as long as the engine.
    func direct(_ buffer: jobject?) -> UnsafeRawBufferPointer? {
        guard let buffer, let start = jni.GetDirectBufferAddress(self, buffer) else { return nil }
        return UnsafeRawBufferPointer(start: start, count: Int(jni.GetDirectBufferCapacity(self, buffer)))
    }

    func method(_ object: jobject, _ name: String, _ signature: String) -> jmethodID? {
        let type = jni.GetObjectClass(self, object)
        defer { jni.DeleteLocalRef(self, type) }
        return jni.GetMethodID(self, type, name, signature)
    }
}
