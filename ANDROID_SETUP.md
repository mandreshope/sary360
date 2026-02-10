# Configuration Android

## Permissions à ajouter manuellement

Ouvrez le fichier `android/app/src/main/AndroidManifest.xml` et ajoutez les lignes suivantes **APRÈS** la ligne `<manifest xmlns:android="http://schemas.android.com/apk/res/android">` et **AVANT** `<application` :

```xml
    <!-- Permissions requises pour Sary360 -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    
    <!-- Features requises -->
    <uses-feature android:name="android.hardware.camera" android:required="true" />
    <uses-feature android:name="android.hardware.sensor.gyroscope" android:required="true" />
```

Le fichier devrait ressembler à :

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Permissions requises pour Sary360 -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    
    <!-- Features requises -->
    <uses-feature android:name="android.hardware.camera" android:required="true" />
    <uses-feature android:name="android.hardware.sensor.gyroscope" android:required="true" />
    
    <application
        android:label="sary360"
        ...
```

## MinSDK Version

Dans `android/app/build.gradle`, vérifiez que minSdkVersion est au moins **23** (Android 6.0) :

```gradle
android {
    defaultConfig {
        minSdkVersion 23
        targetSdkVersion 34
        ...
    }
}
```
