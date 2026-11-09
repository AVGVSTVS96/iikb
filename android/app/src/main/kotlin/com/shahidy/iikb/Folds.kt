package com.shahidy.iikb

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager

/**
 * Whether this phone folds: it has a hinge, as each Android foldable reports one. It stays a phone open or folded, as
 * iOS's iPhone Duo does, where a tablet is a tablet (`DeviceClass(screen:folds:)`); which of its screens the keys are
 * on follows the screen's size, never the hinge.
 */
fun Context.folds(): Boolean =
    packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_HINGE_ANGLE) ||
        getSystemService(SensorManager::class.java)?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE) != null
