String fmtCents(dynamic v){
  try{
    final c = (v is int)? v : int.tryParse(v.toString())??0;
    final neg = c<0; int abs = c.abs(); int major = abs ~/ 100; int minor = abs % 100;
    String sMajor = major.toString();
    final reg = RegExp(r"(\d+)(\d{3})");
    while(reg.hasMatch(sMajor)){ sMajor = sMajor.replaceAllMapped(reg, (m)=> "${m.group(1)},${m.group(2)}"); }
    final out = "$sMajor.${minor.toString().padLeft(2,'0')}";
    return neg? "-$out" : out;
  }catch(_){ return v.toString(); }
}
