import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';

/// Network access for the store dashboard. Each method mirrors an inline Dio
/// call that previously lived in store_dashboard.dart; behavior is unchanged.
class StoreRepository {
  StoreRepository(this._dio);

  final Dio _dio;

  // ---- reads ----
  Future<dynamic> fetchStore(int id) async {
    final r = await _dio.get('${Api.stores}$id/');
    return r.data;
  }

  Future<dynamic> fetchProducts(int storeId) async {
    final r = await _dio.get('${Api.products}?store=$storeId');
    return r.data;
  }

  Future<dynamic> fetchOrders() async {
    final r = await _dio.get('/orders/');
    return r.data;
  }

  Future<dynamic> fetchOrderItems() async {
    final r = await _dio.get('/order-items/');
    return r.data;
  }

  Future<dynamic> fetchEscrows() async {
    final r = await _dio.get('/escrows/');
    return r.data;
  }

  Future<dynamic> fetchDeliveryJobs() async {
    final r = await _dio.get('/delivery-jobs/');
    return r.data;
  }

  Future<dynamic> fetchStoreReviews(int storeId) async {
    final r = await _dio.get('/store-reviews/?store=$storeId');
    return r.data;
  }

  Future<dynamic> fetchProductReviews(int productId) async {
    final r = await _dio.get('/product-reviews/?product=$productId');
    return r.data;
  }

  Future<dynamic> fetchFarm(int farmId) async {
    final r = await _dio.get('${Api.farms}$farmId/');
    return r.data;
  }

  Future<dynamic> fetchMe() async {
    final r = await _dio.get(Api.me);
    return r.data;
  }

  Future<dynamic> fetchPayout() async {
    final r = await _dio.get('/payout-accounts/');
    return r.data;
  }

  Future<dynamic> fetchPayoutBanks() async {
    final r = await _dio.get('/payout-accounts/banks/');
    return r.data;
  }

  Future<dynamic> fetchAds(int storeId) async {
    final r = await _dio.get('/advertisements/?store=$storeId');
    return r.data;
  }

  // ---- product mutations ----
  Future<void> updateProductPublished(int id, bool published) async {
    await _dio.patch('${Api.products}$id/', data: {'is_published': published});
  }

  Future<void> deleteProduct(int id) async {
    await _dio.delete('${Api.products}$id/');
  }

  Future<void> createProduct(dynamic body) async {
    await _dio.post(Api.products, data: body);
  }

  Future<void> updateProduct(int id, dynamic body) async {
    await _dio.patch('${Api.products}$id/', data: body);
  }

  Future<void> updateProductStock(int id, num qty) async {
    await _dio.patch('${Api.products}$id/', data: {'stock_quantity': qty});
  }

  // ---- order mutations ----
  Future<void> updateOrderStatus(int id, String status) async {
    await _dio.patch('/orders/$id/', data: {'status': status});
  }

  // ---- escrow ----
  Future<void> issueOtp(int eid, dynamic data) async {
    await _dio.post('/escrows/$eid/issue_otp/', data: data);
  }

  Future<void> confirmDelivery(int eid, String otp) async {
    await _dio.post('/escrows/$eid/confirm_delivery/', data: {'otp': otp});
  }

  Future<dynamic> createEscrow(Map<String, dynamic> body) async {
    final r = await _dio.post('/escrows/', data: body);
    return r.data;
  }

  Future<dynamic> payEscrow(int eid) async {
    final r = await _dio.post('/escrows/$eid/pay/');
    return r.data;
  }

  Future<void> releaseEscrow(int eid) async {
    await _dio.post('/escrows/$eid/release/');
  }

  // ---- payout accounts ----
  Future<void> updatePayoutAccount(int id, Map<String, dynamic> payload) async {
    await _dio.patch('/payout-accounts/$id/', data: payload);
  }

  Future<void> createPayoutAccount(Map<String, dynamic> payload) async {
    await _dio.post('/payout-accounts/', data: payload);
  }

  // ---- advertisements ----
  Future<void> updateAdActive(int id, bool active) async {
    await _dio.patch('/advertisements/$id/', data: {'is_active': active});
  }

  Future<void> deleteAd(int id) async {
    await _dio.delete('/advertisements/$id/');
  }

  Future<void> createAd(dynamic data) async {
    await _dio.post('/advertisements/', data: data);
  }

  // ---- delivery jobs ----
  Future<dynamic> createDeliveryJob(Map<String, dynamic> body) async {
    final r = await _dio.post('/delivery-jobs/', data: body);
    return r.data;
  }

  Future<void> sendRiderLink(int jid, Map<String, dynamic> body) async {
    await _dio.post('/delivery-jobs/$jid/send_link/', data: body);
  }

  Future<void> cancelDeliveryJob(int jid) async {
    await _dio.post('/delivery-jobs/$jid/cancel/');
  }
}
