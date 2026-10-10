/// Photo Sphere (GPano) XMP metadata, so that Google Photos and other viewers
/// open the image as an interactive 360° panorama.
///
/// The image covers the full sphere: the cropped area equals the full
/// panorama. A compliant APP1 placement is planned (step 5 of the roadmap).
List<int> injectPhotoSphereXmp(List<int> jpeg, int width, int height) {
  const String xmpHeader = 'http://ns.adobe.com/xap/1.0/\x00';

  final String xmpContent =
      '''
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Sary360">
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about="" xmlns:GPano="http://ns.google.com/photos/1.0/panorama/">
    <GPano:UsePanoramaViewer>True</GPano:UsePanoramaViewer>
    <GPano:CaptureSoftware>Sary360</GPano:CaptureSoftware>
    <GPano:ProjectionType>equirectangular</GPano:ProjectionType>
    <GPano:PoseHeadingDegrees>0.0</GPano:PoseHeadingDegrees>
    <GPano:CroppedAreaLeftPixels>0</GPano:CroppedAreaLeftPixels>
    <GPano:CroppedAreaTopPixels>0</GPano:CroppedAreaTopPixels>
    <GPano:FullPanoWidthPixels>$width</GPano:FullPanoWidthPixels>
    <GPano:FullPanoHeightPixels>$height</GPano:FullPanoHeightPixels>
    <GPano:CroppedAreaImageWidthPixels>$width</GPano:CroppedAreaImageWidthPixels>
    <GPano:CroppedAreaImageHeightPixels>$height</GPano:CroppedAreaImageHeightPixels>
  </rdf:Description>
</rdf:RDF>
</x:xmpmeta>''';

  final hdrBytes = xmpHeader.codeUnits;
  final cntBytes = xmpContent.codeUnits;
  final int len = 2 + hdrBytes.length + cntBytes.length;

  final app1 = [
    0xFF,
    0xE1,
    (len >> 8) & 0xFF,
    len & 0xFF,
    ...hdrBytes,
    ...cntBytes,
  ];

  if (jpeg.length >= 2 && jpeg[0] == 0xFF && jpeg[1] == 0xD8) {
    return [0xFF, 0xD8, ...app1, ...jpeg.sublist(2)];
  }
  return jpeg;
}
