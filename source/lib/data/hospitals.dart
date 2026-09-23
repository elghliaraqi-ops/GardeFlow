const String kHospitalBouskoura = 'Hôpital Universitaire International Mohammed VI de Bouskoura';
const String kHospitalRabat = 'Hôpital Universitaire International Mohammed VI de Rabat';
const String kHospitalCasa = 'Hôpital Universitaire International Cheikh Khalifa de Casablanca';

const List<String> kHospitals = [
  kHospitalBouskoura,
  kHospitalRabat,
  kHospitalCasa,
];

const Map<String, String> kHospitalDisplayNames = {
  kHospitalBouskoura: 'HUIM6 de Bouskoura',
  kHospitalRabat: 'HUIM6 de Rabat',
  kHospitalCasa: 'HUICK de Casa',
};

String hospitalDisplayName(String hospital) => kHospitalDisplayNames[hospital] ?? hospital;
