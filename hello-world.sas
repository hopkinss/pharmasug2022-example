*------------------------------------------------------------------------*
| Dynamically retrieve the list of all supported languages
| and translate a string, "Hello World!' in English to each language
*------------------------------------------------------------------------*;

*------------------------------------------------------------------------*
| Orgization-specific URL if containerized API used
| Azure subscription key
| Azure region
*------------------------------------------------------------------------*;
%let api=[your API root];
%let key=[your subscription key];
%let region=[your Azure region e.g. westus2];

*------------------------------------------------------------------------*
| Container to hold all the translations
*------------------------------------------------------------------------*;
data all_translations(where=(0));
  length language text $200 code $10;
  call missing(language,text,code);
run;
*---------------------------------------------------------------------*
| Call the languages endpoint to get a list of supported languages
*----------------------------------------------------------------------*;
filename outjson temp;

proc http url="&api/languages?api-version=3.0%nrstr(&scope)=translation"
  METHOD="GET"
  AUTH_NEGOTIATE
  ct="application/json"
  out=outjson;
  headers "accept"="application/json"
          'Ocp-Apim-Subscription-Key'="&key"
          'Ocp-Apim-Subscription-Region'="&region"       
          'content-type'='application/json';
run;

*----------------------------------------------------------------------*
| Get a collection of language codes to pass to the TO parameter in the 
| query string of the Translate endpoign
*----------------------------------------------------------------------*;
libname jsn JSON fileref=outjson;

proc sql noprint;
  select p2,value into :codes separated by '|',:languages separated by '|'
  from jsn.alldata
  where ^missing(p2) and p3='name';
  %let nobs=&sqlobs;
quit;

*------------------------------------------------------------------------*
| Create the hello world JSON file to translate 
*------------------------------------------------------------------------*;
filename jbody "%sysfunc(pathname(work))\jbody.json";

data _null_;
  file jbody;
  put   '[{"text":"Hello World!"}]';
run;
  
*------------------------------------------------------------------------*
| loop through each language code and call the tranlation Endpoint
*------------------------------------------------------------------------*;
%macro hello_world;
  %do i = 1 %to &nobs.;
    filename outjson temp;
    %*---------------------------------------------------------------------*
    | Pass the JSON arguments to the API. Route the response to a temporary file.
    *----------------------------------------------------------------------*; 
    proc http url="&api/translate?api-version=3.0%nrstr(&from)=en%nrstr(&to)=%scan(&codes,&i,|)"
      METHOD="POST"
      AUTH_NEGOTIATE
      in=jbody
      ct="application/json"
      out=outjson;
      headers "accept"="application/json"
              'Ocp-Apim-Subscription-Key'="&key"
              'Ocp-Apim-Subscription-Region'="&region"       
              'content-type'='application/json';
    run;

    %*---------------------------------------------------------------------*
    | Parse JSON response and append to container dataset
    *----------------------------------------------------------------------*;
    libname jsn JSON fileref=outjson;

    data trn; 
      length text language $200 code $10;
      set jsn.translations(keep=text to rename=(to = code));
      language=strip(scan("&languages",&i.,'|'));
    run;

    proc append base=all_translations data=trn;
    run;
  %end;
%mend;
%hello_world;
 
