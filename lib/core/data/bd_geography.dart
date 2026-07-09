/// Static reference data for Bangladesh's administrative hierarchy
/// (division -> district -> upazilas), used to populate the mandatory
/// permanent-address cascading dropdowns in complete_profile_screen.dart.
/// This is fixed government administrative data that doesn't change and
/// needs no admin CRUD, so it's a plain Dart const rather than a DB table.
class BdGeography {
  BdGeography._();

  /// Dhaka District's real upazila list below covers only the rural area
  /// outside the city -- Dhaka city proper isn't subdivided into upazilas
  /// at all, it's policed/administered as 50 thanas under Dhaka
  /// Metropolitan Police (DNCC + DSCC). This synthetic entry stands in for
  /// "the city itself" in the upazila dropdown; selecting it reveals
  /// [dhakaThanas] as a 4th cascading level instead of the address
  /// stopping one level short for the exact users most likely to use it.
  static const dhakaMahanagarLabel = 'Dhaka Mahanagar (Dhaka City)';

  /// Division name -> District name -> list of Upazila names.
  static const Map<String, Map<String, List<String>>> data = {
    'Barisal': {
      'Barishal': ['Agailjhara', 'Babuganj', 'Bakerganj', 'Banaripara', 'Gaurnadi', 'Hizla', 'Barishal Sadar', 'Mehendiganj', 'Muladi', 'Wazirpur'],
      'Barguna': ['Amtali', 'Bamna', 'Barguna Sadar', 'Betagi', 'Patharghata', 'Taltali'],
      'Bhola': ['Bhola Sadar', 'Burhanuddin', 'Char Fasson', 'Daulatkhan', 'Lalmohan', 'Manpura', 'Tazumuddin'],
      'Jhalokati': ['Jhalokati Sadar', 'Kathalia', 'Nalchity', 'Rajapur'],
      'Patuakhali': ['Bauphal', 'Dashmina', 'Dumki', 'Galachipa', 'Kalapara', 'Mirzaganj', 'Patuakhali Sadar', 'Rangabali'],
      'Pirojpur': ['Bhandaria', 'Indurkani', 'Kawkhali', 'Mathbaria', 'Nazirpur', "Nesarabad (Swarupkati)", 'Pirojpur Sadar'],
    },
    'Chattogram': {
      'Chattogram': ['Anwara', 'Banshkhali', 'Boalkhali', 'Chandanaish', 'Fatikchhari', 'Hathazari', 'Lohagara', 'Mirsharai', 'Patiya', 'Rangunia', 'Raozan', 'Sandwip', 'Satkania', 'Sitakunda', 'Karnaphuli'],
      'Bandarban': ['Ali Kadam', 'Bandarban Sadar', 'Lama', 'Naikhongchhari', 'Rowangchhari', 'Ruma', 'Thanchi'],
      'Brahmanbaria': ['Akhaura', 'Bancharampur', 'Brahmanbaria Sadar', 'Kasba', 'Nabinagar', 'Nasirnagar', 'Sarail', 'Ashuganj', 'Bijoynagar'],
      'Chandpur': ['Chandpur Sadar', 'Faridganj', 'Haimchar', 'Haziganj', 'Kachua', 'Matlab Dakshin', 'Matlab Uttar', 'Shahrasti'],
      'Cumilla': ['Barura', 'Brahmanpara', 'Burichang', 'Chandina', 'Chauddagram', 'Daudkandi', 'Debidwar', 'Homna', 'Laksam', 'Cumilla Adarsha Sadar', 'Meghna', 'Monohargonj', 'Muradnagar', 'Nangalkot', 'Cumilla Sadar Dakshin', 'Titas', 'Lalmai'],
      "Cox's Bazar": ['Chakaria', "Cox's Bazar Sadar", 'Kutubdia', 'Maheshkhali', 'Ramu', 'Teknaf', 'Ukhia', 'Pekua', 'Matamuhuri'],
      'Feni': ['Chhagalnaiya', 'Daganbhuiyan', 'Feni Sadar', 'Parshuram', 'Sonagazi', 'Fulgazi'],
      'Khagrachhari': ['Dighinala', 'Khagrachhari Sadar', 'Lakshmichhari', 'Mahalchhari', 'Manikchhari', 'Matiranga', 'Panchhari', 'Ramgarh', 'Guimara'],
      'Lakshmipur': ['Lakshmipur Sadar', 'Raipur', 'Ramganj', 'Ramgati', 'Kamalnagar', 'Chandraganj'],
      'Noakhali': ['Begumganj', 'Chatkhil', 'Companiganj', 'Hatiya', 'Noakhali Sadar', 'Senbagh', 'Subarnachar', 'Sonaimuri', 'Kabirhat'],
      'Rangamati': ['Bagaichhari', 'Barkal', 'Kawkhali', 'Belaichhari', 'Kaptai', 'Juraichhari', 'Langadu', 'Naniarchar', 'Rajasthali', 'Rangamati Sadar'],
    },
    'Dhaka': {
      'Dhaka': ['Dhamrai', 'Dohar', 'Keraniganj', 'Nawabganj', 'Savar', dhakaMahanagarLabel],
      'Faridpur': ['Alfadanga', 'Bhanga', 'Boalmari', 'Charbhadrasan', 'Faridpur Sadar', 'Madhukhali', 'Nagarkanda', 'Sadarpur', 'Saltha'],
      'Gazipur': ['Gazipur Sadar', 'Kaliakair', 'Kaliganj', 'Kapasia', 'Sreepur'],
      'Gopalganj': ['Gopalganj Sadar', 'Kashiani', 'Kotalipara', 'Muksudpur', 'Tungipara'],
      'Kishoreganj': ['Astagram', 'Bajitpur', 'Bhairab', 'Hossainpur', 'Itna', 'Karimganj', 'Katiadi', 'Kishoreganj Sadar', 'Kuliarchar', 'Mithamain', 'Nikli', 'Pakundia', 'Tarail'],
      'Madaripur': ['Kalkini', 'Madaripur Sadar', 'Rajoir', 'Shibchar', 'Dasar'],
      'Manikganj': ['Daulatpur', 'Ghior', 'Harirampur', 'Manikganj Sadar', 'Saturia', 'Shibalaya', 'Singair'],
      'Munshiganj': ['Gazaria', 'Louhajang', 'Munshiganj Sadar', 'Sirajdikhan', 'Sreenagar', 'Tongibari'],
      'Narayanganj': ['Araihazar', 'Bandar', 'Narayanganj Sadar', 'Rupganj', 'Sonargaon'],
      'Narsingdi': ['Belabo', 'Monohardi', 'Narsingdi Sadar', 'Palash', 'Raipura', 'Shibpur'],
      'Rajbari': ['Baliakandi', 'Goalanda', 'Pangsha', 'Rajbari Sadar', 'Kalukhali'],
      'Shariatpur': ['Bhedarganj', 'Damudya', 'Gosairhat', 'Naria', 'Shariatpur Sadar', 'Zanjira'],
      'Tangail': ['Gopalpur', 'Basail', 'Bhuapur', 'Delduar', 'Ghatail', 'Kalihati', 'Madhupur', 'Mirzapur', 'Nagarpur', 'Sakhipur', 'Tangail Sadar', 'Dhanbari'],
    },
    'Khulna': {
      'Khulna': ['Batiaghata', 'Dacope', 'Dumuria', 'Dighalia', 'Koyra', 'Paikgachha', 'Phultala', 'Rupsha', 'Terokhada'],
      'Bagerhat': ['Bagerhat Sadar', 'Chitalmari', 'Fakirhat', 'Kachua', 'Mollahat', 'Mongla', 'Morrelganj', 'Rampal', 'Sarankhola'],
      'Chuadanga': ['Alamdanga', 'Chuadanga Sadar', 'Damurhuda', 'Jibannagar'],
      'Jashore': ['Abhaynagar', 'Bagherpara', 'Chaugachha', 'Jashore Sadar', 'Jhikargachha', 'Keshabpur', 'Manirampur', 'Sharsha'],
      'Jhenaidah': ['Harinakunda', 'Jhenaidah Sadar', 'Kaliganj', 'Kotchandpur', 'Maheshpur', 'Shailkupa'],
      'Kushtia': ['Bheramara', 'Daulatpur', 'Khoksa', 'Kumarkhali', 'Kushtia Sadar', 'Mirpur'],
      'Magura': ['Magura Sadar', 'Mohammadpur', 'Shalikha', 'Sreepur'],
      'Meherpur': ['Gangni', 'Meherpur Sadar', 'Mujibnagar'],
      'Narail': ['Kalia', 'Lohagara', 'Narail Sadar'],
      'Satkhira': ['Assasuni', 'Debhata', 'Kalaroa', 'Kaliganj', 'Satkhira Sadar', 'Shyamnagar', 'Tala'],
    },
    'Mymensingh': {
      'Mymensingh': ['Bhaluka', 'Dhobaura', 'Fulbaria', 'Gaffargaon', 'Gauripur', 'Haluaghat', 'Ishwarganj', 'Mymensingh Sadar', 'Muktagachha', 'Nandail', 'Phulpur', 'Trishal', 'TaraKanda'],
      'Jamalpur': ['Baksiganj', 'Dewanganj', 'Islampur', 'Jamalpur Sadar', 'Madarganj', 'Melandaha', 'Sarishabari'],
      'Netrokona': ['Atpara', 'Barhatta', 'Durgapur', 'Kalmakanda', 'Kendua', 'Khaliajuri', 'Madan', 'Mohanganj', 'Netrokona Sadar', 'Purbadhala'],
      'Sherpur': ['Jhenaigati', 'Nakla', 'Nalitabari', 'Sherpur Sadar', 'Sreebardi'],
    },
    'Rajshahi': {
      'Rajshahi': ['Bagha', 'Bagmara', 'Charghat', 'Durgapur', 'Godagari', 'Mohanpur', 'Paba', 'Puthia', 'Tanore'],
      'Bogura': ['Adamdighi', 'Bogura Sadar', 'Dhunat', 'Dhupchanchia', 'Gabtali', 'Kahaloo', 'Nandigram', 'Sariakandi', 'Shajahanpur', 'Sherpur', 'Sonatala', 'Shibganj', 'Mokamtola'],
      'Chapai Nawabganj': ['Bholahat', 'Gomastapur', 'Nachole', 'Nawabganj Sadar', 'Shibganj'],
      'Joypurhat': ['Akkelpur', 'Joypurhat Sadar', 'Kalai', 'Khetlal', 'Panchbibi'],
      'Naogaon': ['Atrai', 'Badalgachhi', 'Manda', 'Dhamoirhat', 'Mahadebpur', 'Naogaon Sadar', 'Niamatpur', 'Patnitala', 'Porsha', 'Raninagar', 'Sapahar'],
      'Natore': ['Bagatipara', 'Baraigram', 'Gurudaspur', 'Lalpur', 'Natore Sadar', 'Singra', 'Naldanga'],
      'Pabna': ['Atgharia', 'Bera', 'Bhangura', 'Chatmohar', 'Faridpur', 'Ishwardi', 'Santhia', 'Sujanagar', 'Pabna Sadar'],
      'Sirajganj': ['Belkuchi', 'Chauhali', 'Kamarkhanda', 'Kazipur', 'Raiganj', 'Shahjadpur', 'Sirajganj Sadar', 'Tarash', 'Ullahpara'],
    },
    'Rangpur': {
      'Rangpur': ['Badarganj', 'Gangachhara', 'Kaunia', 'Mithapukur', 'Pirgachha', 'Pirganj', 'Rangpur Sadar', 'Taraganj'],
      'Dinajpur': ['Birampur', 'Birganj', 'Birol', 'Bochaganj', 'Chirirbandar', 'Phulbari', 'Ghoraghat', 'Hakimpur', 'Kaharole', 'Khansama', 'Dinajpur Sadar', 'Nawabganj', 'Parbatipur'],
      'Gaibandha': ['Phulchhari', 'Gaibandha Sadar', 'Gobindaganj', 'Palashbari', 'Sadullapur', 'Sughatta', 'Sundarganj'],
      'Kurigram': ['Bhurungamari', 'Char Rajibpur', 'Chilmari', 'Phulbari', 'Kurigram Sadar', 'Nageshwari', 'Rajarhat', 'Raumari', 'Ulipur'],
      'Lalmonirhat': ['Aditmari', 'Hatibandha', 'Kaliganj', 'Lalmonirhat Sadar', 'Patgram'],
      'Nilphamari': ['Dimla', 'Domar', 'Jaldhaka', 'Kishoreganj', 'Nilphamari Sadar', 'Saidpur'],
      'Panchagarh': ['Atwari', 'Boda', 'Debiganj', 'Panchagarh Sadar', 'Tetulia'],
      'Thakurgaon': ['Baliadangi', 'Haripur', 'Pirganj', 'Ranisankail', 'Thakurgaon Sadar', 'Ruhia', 'Bhully'],
    },
    'Sylhet': {
      'Sylhet': ['Balaganj', 'Beanibazar', 'Bishwanath', 'Fenchuganj', 'Golapganj', 'Gowainghat', 'Jaintiapur', 'Kanaighat', 'Sylhet Sadar', 'Zakiganj', 'Companiganj', 'Dakshin Surma', 'Osmani Nagar'],
      'Habiganj': ['Ajmiriganj', 'Bahubal', 'Baniyachong', 'Chunarughat', 'Habiganj Sadar', 'Lakhai', 'Madhabpur', 'Nabiganj', 'Shayestaganj'],
      'Moulvibazar': ['Barlekha', 'Kamalganj', 'Kulaura', 'Moulvibazar Sadar', 'Rajnagar', 'Sreemangal', 'Juri'],
      'Sunamganj': ['Bishwambharpur', 'Chhatak', 'Derai', 'Dharamapasha', 'Dowarabazar', 'Jagannathpur', 'Jamalganj', 'Sullah', 'Sunamganj Sadar', 'Tahirpur', 'Shantiganj (Dakshin Sunamganj)', 'Madhyanagar'],
    },
  };

  static List<String> get divisions => data.keys.toList();

  static List<String> districtsOf(String? division) =>
      division == null ? const [] : (data[division]?.keys.toList() ?? const []);

  static List<String> upazilasOf(String? division, String? district) {
    if (division == null || district == null) return const [];
    return data[division]?[district] ?? const [];
  }

  static bool isDhakaMahanagar(String? division, String? district, String? upazila) =>
      division == 'Dhaka' && district == 'Dhaka' && upazila == dhakaMahanagarLabel;

  /// All 50 Dhaka Metropolitan Police thanas, sourced from DMP's own
  /// published list (cross-checked against Wikipedia's DMP article,
  /// 2026-07) -- real government administrative divisions, not
  /// approximated, since this feeds a mandatory address field.
  static const List<String> dhakaThanas = [
    'Adabor', 'Airport', 'Badda', 'Banani', 'Bangshal', 'Bhashantek',
    'Cantonment', 'Chawkbazar', 'Dakshin Khan', 'Darus Salam', 'Demra',
    'Dhanmondi', 'Gandaria', 'Gulshan', 'Hatirjheel', 'Hazaribagh',
    'Jatrabari', 'Kadamtali', 'Kafrul', 'Kalabagan', 'Kamrangirchar',
    'Khilgaon', 'Khilkhet', 'Kotwali', 'Lalbagh', 'Mirpur Model',
    'Mohammadpur', 'Motijheel', 'Mugda', 'New Market', 'Pallabi',
    'Paltan Model', 'Ramna Model', 'Rampura', 'Rupnagar', 'Sabujbagh',
    'Shah Ali', 'Shahbagh', 'Shahjahanpur', 'Sher-e-Bangla Nagar',
    'Shyampur', 'Sutrapur', 'Tejgaon', 'Tejgaon Industrial', 'Turag',
    'Uttar Khan', 'Uttara East', 'Uttara West', 'Vatara', 'Wari',
  ];
}
