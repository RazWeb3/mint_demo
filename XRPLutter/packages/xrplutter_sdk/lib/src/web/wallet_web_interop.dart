// -------------------------------------------------------
// 目的・役割: Flutter WebでCrossmark/GemWallet拡張の存在検出を提供する。将来的なJS interop呼び出しの受け皿となる。
// 作成日: 2025/11/09
// 
// 更新履歴:
// 2025/11/09 15:35 追記: 署名APIにオプション引数（submit）を追加、アドレス取得（getAddress）とネットワーク取得（getNetwork）を追加。
// 理由: 実ウォレット拡張のAPI差異に対応しやすくし、事前チェック（アカウント整合）を可能にするため。
// 2025/11/09 16:10 変更: 戻り値正規化を拡張し、トップレベルだけでなく result ネスト内の代表キー（txHash/hash/txid/tx_blob/signed/rejected/error/payloadId）も抽出。
// 理由: 拡張の戻り値がネスト構造で返る場合にも、イベント/オーケストレーションが安定して動作するようにするため。
// 2025/11/09 16:42 変更: requestSignCrossmark/requestSignGemWallet のフォールバックを強化し、request(method)形式での呼び出しパターンを追加。
// 理由: 拡張が request({ method: 'sign'|'signAndSubmit', txJson, options }) 形式のみ受け付けるケースへの互換対応。
// 2025/11/09 16:44 変更: 戻り値正規化で response ネスト内の代表キー抽出を追加。
// 理由: 一部拡張が response 配下に tx_blob/hash 等を返す形式に対応するため。
// 2025/11/09 17:22 追記: 代表キーの同義語（txBlob/signedTransaction/uuid/opened/accepted/submitted）抽出に対応。
// 理由: 実拡張のプロパティ名差異に幅広く対応し、SDK側の解釈を安定化するため。
// 2025/11/10 09:05 変更: Crossmark向けフォールバックに xrpl.* 経由の呼び出し（sign/signAndSubmit/request）を追加。
// 理由: request({ method: 'sign'|'signAndSubmit' }) が不一致で "No compatible request signature" に至るケースを回避するため。
// 2025/11/10 12:20 変更: Crossmarkの構造（async/sync/api）に合わせた呼び出し優先順位へ刷新。async.signAndWait を最優先し、sync.sign+api.awaitRequest/sync.getResponse、api.request+awaitRequest を順次フォールバック。
// 理由: ユーザー観測（window.crossmark.async/sync/api の存在、signAndWait/awaitRequestの動作）に基づき、正しいエントリポイントへ統一するため。
// 2025/11/10 10:50 変更: getAddressCrossmark/getNetwork のフォールバックを修正し、トップレベル request が無い環境で crossmark.api.request({ method: 'getAddress'|'getNetwork' }) を利用するようにした。
// 理由: ユーザー観測（typeof window.crossmark.request === 'undefined'、typeof window.crossmark.api.request === 'function'）に基づくAPI配置差異への対応。
// 2025/11/10 10:58 変更: GemWallet向けの署名要求に async/sync/api ベースのフォールバック（api.request+awaitRequest、sync.sign+api.awaitRequest/sync.getResponse）とXRPL名前空間呼び出しを追加。
// 理由: GemWalletでもAPI配置差異に備え、リクエストID/UUID経由の待機に対応してCrossmark同等の堅牢性を確保するため。
// -------------------------------------------------------

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// Webのみで利用されるJSインタロップ系の検出ロジック
import 'dart:html' as html;
import 'dart:js_util' as js_util;

class BrowserWalletInterop {
  BrowserWalletInterop._();
  static final BrowserWalletInterop instance = BrowserWalletInterop._();

  bool get isAvailableCrossmark => _hasProperty('crossmark');
  bool get isAvailableGemWallet => _hasProperty('gemWallet') || _hasProperty('gemwallet') || _hasProperty('gem_wallet');

  bool _hasProperty(String name) {
    try {
      return js_util.hasProperty(html.window, name) && js_util.getProperty(html.window, name) != null;
    } catch (_) {
      return false;
    }
  }

  /// Crossmark拡張に対する署名要求（API名は環境差を吸収し、存在するメソッドにフォールバック）
  Future<Map<String, dynamic>> requestSignCrossmark(Map<String, dynamic> txJson, {Map<String, dynamic>? options}) async {
    final obj = js_util.getProperty(html.window, 'crossmark');
    if (obj == null) {
      throw StateError('Crossmark extension not available');
    }
    final opts = options ?? {'submit': true};
    // 1) async.signAndWait を最優先（submitフラグはoptsに委ねる）
    try {
      if (js_util.hasProperty(obj, 'async')) {
        final asyncObj = js_util.getProperty(obj, 'async');
        if (asyncObj != null && js_util.hasProperty(asyncObj, 'signAndWait')) {
          final p = js_util.callMethod(asyncObj, 'signAndWait', [txJson, opts]);
          final res = await js_util.promiseToFuture(p);
          return _coerceResult(res);
        }
        // signAndSubmit が提供されている場合（環境差吸収）
        if (asyncObj != null && js_util.hasProperty(asyncObj, 'signAndSubmit')) {
          final p = js_util.callMethod(asyncObj, 'signAndSubmit', [txJson, opts]);
          final res = await js_util.promiseToFuture(p);
          return _coerceResult(res);
        }
      }
    } catch (_) {
      // 続行（後段のフォールバックへ）
    }

    // 2) sync.sign -> api.awaitRequest / sync.getResponse
    try {
      if (js_util.hasProperty(obj, 'sync')) {
        final syncObj = js_util.getProperty(obj, 'sync');
        if (syncObj != null && js_util.hasProperty(syncObj, 'sign')) {
          final id = js_util.callMethod(syncObj, 'sign', [txJson, opts]);
          // 可能なら api.awaitRequest で待機
          dynamic apiObj;
          try {
            if (js_util.hasProperty(obj, 'api')) {
              apiObj = js_util.getProperty(obj, 'api');
            }
          } catch (_) {}
          if (apiObj != null && js_util.hasProperty(apiObj, 'awaitRequest')) {
            try {
              final p = js_util.callMethod(apiObj, 'awaitRequest', [id]);
              final res = await js_util.promiseToFuture(p);
              return _coerceResult(res);
            } catch (_) {}
          }
          // awaitRequestが無ければ sync.getResponse を試す
          if (js_util.hasProperty(syncObj, 'getResponse')) {
            try {
              final r = js_util.callMethod(syncObj, 'getResponse', [id]);
              try {
                final res = await js_util.promiseToFuture(r);
                return _coerceResult(res);
              } catch (_) {
                // Promiseでなければそのまま解釈
                return _coerceResult(r);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // 続行
    }

    // 3) api.request + awaitRequest（複数の呼び出しシグネチャを順次試す）
    try {
      dynamic apiObj;
      if (js_util.hasProperty(obj, 'api')) {
        apiObj = js_util.getProperty(obj, 'api');
      }
      if (apiObj != null && js_util.hasProperty(apiObj, 'request')) {
        final reqRes = await js_util.promiseToFuture(_tryRequestCalls(apiObj, txJson, opts));
        // reqResからuuidを抽出（request.uuid / uuid / 文字列）
        dynamic uuid;
        try {
          final r = js_util.getProperty(reqRes, 'request');
          if (r != null) {
            uuid = js_util.getProperty(r, 'uuid');
          }
        } catch (_) {}
        if (uuid == null) {
          try {
            uuid = js_util.getProperty(reqRes, 'uuid');
          } catch (_) {}
        }
        if (uuid == null && reqRes is String) {
          uuid = reqRes;
        }
        // uuidが得られ、awaitRequestが利用可能なら待機して結果へ正規化
        if (uuid != null && js_util.hasProperty(apiObj, 'awaitRequest')) {
          try {
            final p = js_util.callMethod(apiObj, 'awaitRequest', [uuid]);
            final res = await js_util.promiseToFuture(p);
            return _coerceResult(res);
          } catch (_) {}
        }
        // そのまま返却（reqResがresponseを含むケースに対応）
        return _coerceResult(reqRes);
      }
    } catch (_) {
      // 続行
    }

    // 4) 旧来のトップレベル/名前空間付きフォールバック
    dynamic promise;
    if (js_util.hasProperty(obj, 'signAndSubmit')) {
      promise = js_util.callMethod(obj, 'signAndSubmit', [txJson, opts]);
    } else if (js_util.hasProperty(obj, 'sign')) {
      promise = js_util.callMethod(obj, 'sign', [txJson, opts]);
    } else {
      // 追加フォールバック: crossmark.xrpl 経由の呼び出しを試す
      dynamic xrpl;
      try {
        if (js_util.hasProperty(obj, 'xrpl')) {
          xrpl = js_util.getProperty(obj, 'xrpl');
        }
      } catch (_) {}
      if (xrpl != null) {
        try {
          promise = js_util.callMethod(xrpl, 'signAndSubmit', [txJson, opts]);
        } catch (_) {}
        if (promise == null) {
          try {
            promise = js_util.callMethod(xrpl, 'sign', [txJson, opts]);
          } catch (_) {}
        }
        if (promise == null) {
          try {
            promise = _tryRequestCalls(xrpl, txJson, opts);
          } catch (_) {}
        }
      }
      // フォールバック（request形式の複数パターンを試す）
      promise ??= _tryRequestCalls(obj, txJson, opts);
    }
    final res = await js_util.promiseToFuture(promise);
    return _coerceResult(res);
  }

  /// GemWallet拡張に対する署名要求（API名は環境差を吸収し、存在するメソッドにフォールバック）
  Future<Map<String, dynamic>> requestSignGemWallet(Map<String, dynamic> txJson, {Map<String, dynamic>? options}) async {
    dynamic obj = js_util.getProperty(html.window, 'gemWallet');
    obj ??= js_util.getProperty(html.window, 'gemwallet');
    obj ??= js_util.getProperty(html.window, 'gem_wallet');
    if (obj == null) {
      throw StateError('GemWallet extension not available');
    }
    final opts = options ?? {'submit': true};

    // 1) async.signAndWait / async.signAndSubmit を最優先（存在する場合のみ）
    try {
      if (js_util.hasProperty(obj, 'async')) {
        final asyncObj = js_util.getProperty(obj, 'async');
        if (asyncObj != null && js_util.hasProperty(asyncObj, 'signAndWait')) {
          final p = js_util.callMethod(asyncObj, 'signAndWait', [txJson, opts]);
          final res = await js_util.promiseToFuture(p);
          return _coerceResult(res);
        }
        if (asyncObj != null && js_util.hasProperty(asyncObj, 'signAndSubmit')) {
          final p = js_util.callMethod(asyncObj, 'signAndSubmit', [txJson, opts]);
          final res = await js_util.promiseToFuture(p);
          return _coerceResult(res);
        }
      }
    } catch (_) {
      // 続行
    }

    // 2) sync.sign -> api.awaitRequest / sync.getResponse
    try {
      if (js_util.hasProperty(obj, 'sync')) {
        final syncObj = js_util.getProperty(obj, 'sync');
        if (syncObj != null && js_util.hasProperty(syncObj, 'sign')) {
          final id = js_util.callMethod(syncObj, 'sign', [txJson, opts]);
          // 可能なら api.awaitRequest で待機
          dynamic apiObj;
          try {
            if (js_util.hasProperty(obj, 'api')) {
              apiObj = js_util.getProperty(obj, 'api');
            }
          } catch (_) {}
          if (apiObj != null && js_util.hasProperty(apiObj, 'awaitRequest')) {
            try {
              final p = js_util.callMethod(apiObj, 'awaitRequest', [id]);
              final res = await js_util.promiseToFuture(p);
              return _coerceResult(res);
            } catch (_) {}
          }
          // awaitRequestが無ければ sync.getResponse を試す
          if (js_util.hasProperty(syncObj, 'getResponse')) {
            try {
              final r = js_util.callMethod(syncObj, 'getResponse', [id]);
              try {
                final res = await js_util.promiseToFuture(r);
                return _coerceResult(res);
              } catch (_) {
                return _coerceResult(r);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // 続行
    }

    // 3) api.request + awaitRequest（複数の呼び出しシグネチャを順次試す）
    try {
      dynamic apiObj;
      if (js_util.hasProperty(obj, 'api')) {
        apiObj = js_util.getProperty(obj, 'api');
      }
      if (apiObj != null && js_util.hasProperty(apiObj, 'request')) {
        final reqRes = await js_util.promiseToFuture(_tryRequestCalls(apiObj, txJson, opts));
        // reqResからuuidを抽出
        dynamic uuid;
        try {
          final r = js_util.getProperty(reqRes, 'request');
          if (r != null) {
            uuid = js_util.getProperty(r, 'uuid');
          }
        } catch (_) {}
        if (uuid == null) {
          try {
            uuid = js_util.getProperty(reqRes, 'uuid');
          } catch (_) {}
        }
        if (uuid == null && reqRes is String) {
          uuid = reqRes;
        }
        if (uuid != null && js_util.hasProperty(apiObj, 'awaitRequest')) {
          try {
            final p = js_util.callMethod(apiObj, 'awaitRequest', [uuid]);
            final res = await js_util.promiseToFuture(p);
            return _coerceResult(res);
          } catch (_) {}
        }
        return _coerceResult(reqRes);
      }
    } catch (_) {
      // 続行
    }

    // 4) 旧来のトップレベル/名前空間付きフォールバック
    dynamic promise;
    if (js_util.hasProperty(obj, 'signAndSubmit')) {
      promise = js_util.callMethod(obj, 'signAndSubmit', [txJson, opts]);
    } else if (js_util.hasProperty(obj, 'sign')) {
      promise = js_util.callMethod(obj, 'sign', [txJson, opts]);
    } else {
      // XRPL名前空間付き（gemwallet.xrpl 等）を試行
      dynamic xrpl;
      try {
        if (js_util.hasProperty(obj, 'xrpl')) {
          xrpl = js_util.getProperty(obj, 'xrpl');
        }
      } catch (_) {}
      if (xrpl != null) {
        try {
          promise = js_util.callMethod(xrpl, 'signAndSubmit', [txJson, opts]);
        } catch (_) {}
        if (promise == null) {
          try {
            promise = js_util.callMethod(xrpl, 'sign', [txJson, opts]);
          } catch (_) {}
        }
        if (promise == null) {
          try {
            promise = _tryRequestCalls(xrpl, txJson, opts);
          } catch (_) {}
        }
      }
      promise ??= _tryRequestCalls(obj, txJson, opts);
    }
    final res = await js_util.promiseToFuture(promise);
    return _coerceResult(res);
  }

  /// Crossmark/GemWalletからアドレス取得（存在するメソッド・プロパティにフォールバック）
  Future<String?> getAddressCrossmark() async {
    final obj = js_util.getProperty(html.window, 'crossmark');
    if (obj == null) return null;
    dynamic res;
    try {
      if (js_util.hasProperty(obj, 'getAddress')) {
        res = await js_util.promiseToFuture(js_util.callMethod(obj, 'getAddress', []));
      } else if (js_util.hasProperty(obj, 'address')) {
        res = js_util.getProperty(obj, 'address');
      } else {
        // フォールバック: crossmark.api.request({ method: 'getAddress' })
        dynamic apiObj;
        try {
          if (js_util.hasProperty(obj, 'api')) {
            apiObj = js_util.getProperty(obj, 'api');
          }
        } catch (_) {}
        if (apiObj != null && js_util.hasProperty(apiObj, 'request')) {
          final p = js_util.callMethod(apiObj, 'request', [
            {
              'method': 'getAddress',
            }
          ]);
          res = await js_util.promiseToFuture(p);
        } else if (js_util.hasProperty(obj, 'request')) {
          // 旧来のトップレベル request がある場合のみ試行
          final p = js_util.callMethod(obj, 'request', [
            {
              'method': 'getAddress',
            }
          ]);
          res = await js_util.promiseToFuture(p);
        } else {
          return null;
        }
      }
    } catch (_) {
      return null;
    }
    return _coerceToString(res);
  }

  Future<String?> getAddressGemWallet() async {
    dynamic obj = js_util.getProperty(html.window, 'gemWallet');
    obj ??= js_util.getProperty(html.window, 'gemwallet');
    obj ??= js_util.getProperty(html.window, 'gem_wallet');
    if (obj == null) return null;
    dynamic res;
    try {
      if (js_util.hasProperty(obj, 'getAddress')) {
        res = await js_util.promiseToFuture(js_util.callMethod(obj, 'getAddress', []));
      } else if (js_util.hasProperty(obj, 'address')) {
        res = js_util.getProperty(obj, 'address');
      } else {
        res = await js_util.promiseToFuture(js_util.callMethod(obj, 'request', [{'method': 'getAddress'}]));
      }
    } catch (_) {
      return null;
    }
    return _coerceToString(res);
  }

  /// ネットワーク識別子の取得（可能なら）
  Future<String?> getNetwork() async {
    // シンプルに window のプロパティから拾う試み（API差異に対応）
    final cross = js_util.getProperty(html.window, 'crossmark');
    final gem = js_util.getProperty(html.window, 'gemWallet') ?? js_util.getProperty(html.window, 'gemwallet') ?? js_util.getProperty(html.window, 'gem_wallet');
    dynamic res;
    for (final obj in [cross, gem]) {
      if (obj == null) continue;
      try {
        if (js_util.hasProperty(obj, 'getNetwork')) {
          res = await js_util.promiseToFuture(js_util.callMethod(obj, 'getNetwork', []));
          if (res != null) return _coerceToString(res);
        } else if (js_util.hasProperty(obj, 'network')) {
          res = js_util.getProperty(obj, 'network');
          if (res != null) return _coerceToString(res);
        } else {
          // フォールバック: api.request({ method: 'getNetwork' })
          dynamic apiObj;
          try {
            if (js_util.hasProperty(obj, 'api')) {
              apiObj = js_util.getProperty(obj, 'api');
            }
          } catch (_) {}
          if (apiObj != null && js_util.hasProperty(apiObj, 'request')) {
            try {
              final p = js_util.callMethod(apiObj, 'request', [
                {
                  'method': 'getNetwork',
                }
              ]);
              res = await js_util.promiseToFuture(p);
              if (res != null) return _coerceToString(res);
            } catch (_) {}
          } else if (js_util.hasProperty(obj, 'request')) {
            try {
              final p = js_util.callMethod(obj, 'request', [
                {
                  'method': 'getNetwork',
                }
              ]);
              res = await js_util.promiseToFuture(p);
              if (res != null) return _coerceToString(res);
            } catch (_) {}
          }
        }
      } catch (_) {
        // ignore and continue
      }
    }
    return null;
  }

  Map<String, dynamic> _coerceResult(dynamic obj) {
    // JSオブジェクト/Mapの違いを吸収して代表的なキーを抽出
    final keys = [
      'txHash',
      'hash',
      'txid',
      'tx_blob',
      // 同義語
      'txBlob',
      'signedTransaction',
      'signed',
      'rejected',
      'error',
      'result',
      'response',
      'request',
      'payloadId',
      // payload IDの同義語
      'uuid',
      // 参考フラグ
      'opened',
      'accepted',
      'submitted',
    ];
    final out = <String, dynamic>{};
    for (final k in keys) {
      try {
        if (obj is Map) {
          if (obj.containsKey(k)) out[k] = obj[k];
        } else {
          final v = js_util.getProperty(obj, k);
          if (v != null) out[k] = v;
        }
      } catch (_) {
        // ignore individual property errors
      }
    }
    // ネストされた result 内の代表キーも抽出（上書きは行わず、未設定のみ補完）
    dynamic nested = out['result'];
    if (nested != null) {
      final nestedOut = <String, dynamic>{};
      for (final k in [
        'txHash',
        'hash',
        'txid',
        'tx_blob',
        'txBlob',
        'signedTransaction',
        'signed',
        'rejected',
        'error',
        'payloadId',
        'uuid',
        'opened',
        'accepted',
        'submitted',
      ]) {
        try {
          if (nested is Map) {
            if (nested.containsKey(k)) nestedOut[k] = nested[k];
          } else {
            final v = js_util.getProperty(nested, k);
            if (v != null) nestedOut[k] = v;
          }
        } catch (_) {}
      }
      // 既に out に値があるキーは尊重し、未設定のみ補完
      nestedOut.forEach((key, value) {
        if (!out.containsKey(key)) {
          out[key] = value;
        }
      });
    }
    // ネストされた response 内の代表キーも抽出
    dynamic respNested = out['response'];
    if (respNested != null) {
      final nestedOut = <String, dynamic>{};
      for (final k in [
        'txHash',
        'hash',
        'txid',
        'tx_blob',
        'txBlob',
        'signedTransaction',
        'signed',
        'rejected',
        'error',
        'payloadId',
        'uuid',
        'opened',
        'accepted',
        'submitted',
      ]) {
        try {
          if (respNested is Map) {
            if (respNested.containsKey(k)) nestedOut[k] = respNested[k];
          } else {
            final v = js_util.getProperty(respNested, k);
            if (v != null) nestedOut[k] = v;
          }
        } catch (_) {}
      }
      nestedOut.forEach((key, value) {
        if (!out.containsKey(key)) {
          out[key] = value;
        }
      });
    }
    // ネストされた request 内の代表キー（uuid/payloadId 等）も抽出
    dynamic reqNested = out['request'];
    if (reqNested != null) {
      final nestedOut = <String, dynamic>{};
      for (final k in [
        'uuid',
        'payloadId',
      ]) {
        try {
          if (reqNested is Map) {
            if (reqNested.containsKey(k)) nestedOut[k] = reqNested[k];
          } else {
            final v = js_util.getProperty(reqNested, k);
            if (v != null) nestedOut[k] = v;
          }
        } catch (_) {}
      }
      nestedOut.forEach((key, value) {
        if (!out.containsKey(key)) {
          out[key] = value;
        }
      });
    }
    return out;
  }

  /// request呼び出しのフォールバックを順に試す
  dynamic _tryRequestCalls(dynamic obj, Map<String, dynamic> txJson, Map<String, dynamic> opts) {
    // パターン0: request('signAndSubmit', { txJson, options }) / request('sign', { txJson, options })
    try {
      return js_util.callMethod(obj, 'request', ['signAndSubmit', {
        'txJson': txJson,
        'options': opts,
      }]);
    } catch (_) {}
    try {
      return js_util.callMethod(obj, 'request', ['sign', {
        'txJson': txJson,
        'options': opts,
      }]);
    } catch (_) {}
    // パターン0b: request({ method: 'signAndSubmit', params: { txJson, options } }) / 同sign
    try {
      final payload = {
        'method': 'signAndSubmit',
        'params': {
          'txJson': txJson,
          'options': opts,
        },
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    try {
      final payload = {
        'method': 'sign',
        'params': {
          'txJson': txJson,
          'options': opts,
        },
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    // パターン1: request({ method: 'signAndSubmit', txJson, options })
    try {
      final payload = {
        'method': 'signAndSubmit',
        'txJson': txJson,
        'options': opts,
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    // パターン2: request({ method: 'sign', txJson, options })
    try {
      final payload = {
        'method': 'sign',
        'txJson': txJson,
        'options': opts,
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    // パターン3: request(txJson, opts)
    try {
      return js_util.callMethod(obj, 'request', [txJson, opts]);
    } catch (_) {}
    // 最終フォールバック: request({ tx: txJson, options })
    try {
      final payload = {
        'tx': txJson,
        'options': opts,
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    // XRPL名前空間付きのメソッド名を試す
    try {
      final payload = {
        'method': 'xrpl.signAndSubmit',
        'txJson': txJson,
        'options': opts,
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    try {
      final payload = {
        'method': 'xrpl.sign',
        'txJson': txJson,
        'options': opts,
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    try {
      final payload = {
        'method': 'xrpl.signAndSubmit',
        'params': {
          'txJson': txJson,
          'options': opts,
        },
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    try {
      final payload = {
        'method': 'xrpl.sign',
        'params': {
          'txJson': txJson,
          'options': opts,
        },
      };
      return js_util.callMethod(obj, 'request', [payload]);
    } catch (_) {}
    throw StateError('No compatible request signature');
  }

  String? _coerceToString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    try {
      return v.toString();
    } catch (_) {
      return null;
    }
  }
}