// Translation dictionaries and locale metadata for the app.
//
// Ported from the web app's `static/i18n.js`. As on the web, only French is
// currently populated; other languages fall back to the English key. Add
// entries per language as strings are localised — keys are the English source
// text, matching the `context.tr('English text')` lookup.

/// A supported app language.
class AppLanguage {
  final String code; // ISO 639-1
  final String name; // endonym shown in the picker
  final bool rtl;
  const AppLanguage(this.code, this.name, {this.rtl = false});
}

/// The same six languages offered by the web authentication selector.
const List<AppLanguage> kLanguages = [
  AppLanguage('en', 'English'),
  AppLanguage('fr', 'Français'),
  AppLanguage('es', 'Español'),
  AppLanguage('pt', 'Português'),
  AppLanguage('sw', 'Kiswahili'),
  AppLanguage('ar', 'العربية', rtl: true),
];

/// A supported currency with its display symbol.
class AppCurrency {
  final String code;
  final String symbol;
  final String name;
  const AppCurrency(this.code, this.symbol, this.name);
}

/// Currencies from the web currency map plus the common East/West African ones
/// referenced across the app.
const List<AppCurrency> kCurrencies = [
  AppCurrency('USD', '\$', 'US Dollar'),
  AppCurrency('EUR', '€', 'Euro'),
  AppCurrency('NGN', '₦', 'Nigerian Naira'),
  AppCurrency('KES', 'KSh', 'Kenyan Shilling'),
  AppCurrency('UGX', 'USh', 'Ugandan Shilling'),
  AppCurrency('TZS', 'TSh', 'Tanzanian Shilling'),
  AppCurrency('GHS', '₵', 'Ghanaian Cedi'),
  AppCurrency('ZAR', 'R', 'South African Rand'),
  AppCurrency('RWF', 'FRw', 'Rwandan Franc'),
];

AppCurrency currencyFor(String code) =>
    kCurrencies.firstWhere((c) => c.code == code,
        orElse: () => kCurrencies.first);

bool isRtlLanguage(String code) =>
    kLanguages.any((l) => l.code == code && l.rtl);

/// key (English source) -> translated string, per language code.
const Map<String, Map<String, String>> kTranslations = {
  'en': {},
  'fr': {
    // Workforce / professional network (mirrors web i18n.js)
    'Professional Network': 'Réseau professionnel',
    'Connect with skilled professionals to power your farm work':
        'Connectez-vous avec des professionnels qualifiés pour dynamiser votre ferme',
    'All': 'Tous',
    'Agronomists': 'Agronomes',
    'Veterinarians': 'Vétérinaires',
    'Mechanics': 'Mécaniciens',
    'Farm Managers': 'Gestionnaires de ferme',
    'Livestock Handlers': 'Manieurs de bétail',
    'Minimum Rating': 'Note minimale',
    'Availability': 'Disponibilité',
    'Any Rating': 'Toute note',
    'Available Now': 'Disponible maintenant',
    'Full-Time': 'Temps plein',
    'Part-Time': 'Temps partiel',
    'Contract': 'Contrat',
    'Highest Rated': 'Mieux noté',
    'Most Experienced': 'Le plus expérimenté',
    'Newest': 'Le plus récent',
    'Professionals Available': 'Professionnels disponibles',
    'No professionals found': 'Aucun professionnel trouvé',
    'Try adjusting your filters': 'Essayez de modifier vos filtres',
    'View Profile': 'Voir le profil',
    'About': 'À propos',
    'Skills': 'Compétences',
    // Shared navigation / settings strings
    'Market': 'Marché',
    'Farms': 'Fermes',
    'Stores': 'Boutiques',
    'Chats': 'Discussions',
    'Workforce': 'Main-d’œuvre',
    'Wallet': 'Portefeuille',
    'Profile': 'Profil',
    'Settings': 'Paramètres',
    'Language': 'Langue',
    'Currency': 'Devise',
    'Log out': 'Se déconnecter',
    'More': 'Plus',
    'Finances': 'Finances',
    'Transporter': 'Transporteur',
    // Common actions
    'Add': 'Ajouter',
    'Edit': 'Modifier',
    'Save': 'Enregistrer',
    'Delete': 'Supprimer',
    'Cancel': 'Annuler',
    'Retry': 'Réessayer',
    'Search': 'Rechercher',
    'Close': 'Fermer',
    'Confirm': 'Confirmer',
    'Submit': 'Envoyer',
    'Done': 'Terminé',
    'Continue': 'Continuer',
    'Back': 'Retour',
    // Common states
    'Loading…': 'Chargement…',
    'No results': 'Aucun résultat',
    'Something went wrong': 'Une erreur est survenue',
    'Pull down to retry': 'Tirez vers le bas pour réessayer',
    // Marketplace
    'Marketplace': 'Marché',
    'Cart': 'Panier',
    'Checkout': 'Commander',
    'Add to cart': 'Ajouter au panier',
    'Out of stock': 'Rupture de stock',
    'Price': 'Prix',
    'Category': 'Catégorie',
    'Featured': 'En vedette',
    // Farms
    'Add farm': 'Ajouter une ferme',
    'Crops': 'Cultures',
    'Livestock': 'Bétail',
    'Land': 'Terres',
    'Fields': 'Parcelles',
    'Expenses': 'Dépenses',
    'Produce': 'Production',
    // Stores
    'Add store': 'Ajouter une boutique',
    'Orders': 'Commandes',
    'Products': 'Produits',
    'Reviews': 'Avis',
    'Verified': 'Vérifié',
    // Wallet / finance
    'Balance': 'Solde',
    'Available balance': 'Solde disponible',
    'Payout destination': 'Destination de paiement',
    'Mobile money': 'Argent mobile',
    'Bank': 'Banque',
    'Revenue': 'Revenus',
    'Net profit': 'Bénéfice net',
    'Margin': 'Marge',
    // Chats
    'Messages': 'Messages',
    'New message': 'Nouveau message',
    'Type a message…': 'Écrivez un message…',
    'Online': 'En ligne',
    'Offline': 'Hors ligne',
  },
  'es': {},
  'pt': {},
  'sw': {},
  'ar': {},
};
