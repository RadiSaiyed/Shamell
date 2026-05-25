const String kShamellSupportEmail = 'radisaiyed@icloud.com';
const String kShamellSupportPhone = '+963996428955';

Uri shamellSupportEmailUri({required String subject}) {
  return Uri(
    scheme: 'mailto',
    path: kShamellSupportEmail,
    queryParameters: <String, String>{'subject': subject},
  );
}

Uri shamellSupportPhoneUri() {
  return Uri(
    scheme: 'tel',
    path: kShamellSupportPhone,
  );
}
