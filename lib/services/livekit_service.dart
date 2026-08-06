import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';


class LiveKitService {

  LiveKitService._();

  static final LiveKitService instance =
      LiveKitService._();



  /// Récupération du token JWT LiveKit
  Future<String?> fetchToken({

    required String room,

    required String identity,

    required String name,

    bool isHost = false,

  }) async {


    final candidates = _buildCandidates();



    for(final baseUrl in candidates){


      try{


        final token =
        await _fetchFromServer(

          baseUrl: baseUrl,

          room: room,

          identity: identity,

          name: name,

          isHost: isHost,

        );



        if(token != null){

          return token;

        }



      }catch(e){


        dev.log(

          'LiveKit token error $baseUrl : $e',

          name:'crux'

        );


      }


    }



    return null;

  }






  Future<String?> _fetchFromServer({


    required String baseUrl,

    required String room,

    required String identity,

    required String name,

    required bool isHost,


  }) async {



    final user =
    FirebaseAuth.instance.currentUser;



    if(user == null){


      dev.log(

        'Utilisateur Firebase absent',

        name:'crux'

      );


      return null;

    }





    final firebaseToken =
    await user.getIdToken(true);





    final uri =
    Uri.parse(

      '$baseUrl/livekit-token'

    ).replace(


      queryParameters:{


        'room':room,


        'identity':identity,


        'name':name,


        'isHost':
        isHost.toString(),


      }


    );







    final response =
    await http.get(

      uri,


      headers:{


        'Authorization':
        'Bearer $firebaseToken',


        'Content-Type':
        'application/json',


      },


    ).timeout(

      const Duration(seconds:10)

    );







    if(response.statusCode == 200){


      final data =
      jsonDecode(response.body);



      final token =
      data['token'];



      if(token != null &&
          token.toString().isNotEmpty){



        dev.log(

          'Token LiveKit reçu',

          name:'crux'

        );



        return token;


      }


    }






    dev.log(

      'Erreur token ${response.statusCode}: ${response.body}',

      name:'crux'

    );



    return null;


  }







  List<String> _buildCandidates(){


    final urls=<String>{};



    if(kIsWeb){

      try{

        final origin =
        Uri.base.origin;


        if(origin.startsWith('http')){

          urls.add(origin);

        }


      }catch(_){}

    }





    urls.add(

      AppConfig.livekitTokenServerUrl

    );





    for(final url in AppConfig.livekitFallbackUrls){


      if(url.isNotEmpty){

        urls.add(url);

      }


    }





    return urls.toList();


  }


}
