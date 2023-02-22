
*------------------------------------------------------------------------*
| Translate the contents of a dataset from Simplified Chinese to English
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
| Generate a sample dataset with both numeric and character values in 
| Simplified Chinese characters
*------------------------------------------------------------------------*;
data cm;
  length day 8 CMTERM $100 cmcat cmreas $50 visdt 8 trtgrp $2; 
  format visdt date9.;
  infile datalines dlm=',' dsd;
  input visdt:date9. day CMTERM	CMCAT cmreas trtgrp;
  datalines;
  01Jan2022,1,右乳癌改良根治术,化疗,病史,A
  01Jan2022,1,左乳癌改良根治术,化疗,病史,B
  05Jan2022,5,右乳癌改良根治术,靶向治疗,不良事件,C
  08Jan2022,8,甲状腺结节切除术,辐射,预防用药,A
  10Jan2022,10,右乳癌改良根治术,化疗,预防用药,B
  05Jan2022,5,于外院行左侧乳腺肿物切除+左乳癌改,化疗,预防用药,C
  07Jan2022,7,左乳癌改良根治术,靶向治疗,病史,A
  ;
run;

%macro translate( dsn=
                 ,from_lang=
                 ,to_lang=);

  %*---------------------------------------------------------------------*
  | Add a unique identifier ID to the input dataset. Used to join numeric 
  | variables back to the translated character variables
  *----------------------------------------------------------------------*;
  data &dsn._in;
    set &dsn.;
    id+1;
  run;

  %*---------------------------------------------------------------------*
  | Sort character variables first by name. Used to rename response data 
  | from translation API
  *----------------------------------------------------------------------*;
  proc contents data=&dsn. out=&dsn._md(keep=name type length) nodetails noprint;
  run;
  proc sort data=&dsn._md;
    by descending type  name;
  run;

  %*---------------------------------------------------------------------*
  | Capture metadata for character and numeric variables in macro variables
  *----------------------------------------------------------------------*;
  data _null_;
    length cvars nvars $5000 ;
    retain cvars nvars;
    set &dsn._md end=eof;
    by descending type  name;
    %*-------------------------------------------------------------------*
    | Build a list of character variables
    *--------------------------------------------------------------------*;
    if type=2 then do;
      cvars = catx(" ",strip(cvars),strip(name));
      ncvars+1;
    end;
    %*-------------------------------------------------------------------*
    | Build a list of numeric variables - will remain unchanged from input 
    | dataset
    *--------------------------------------------------------------------*;
    else do;
      nvars = catx(" ",strip(nvars),strip(name));
      nnvars+1;
    end;
    if eof then do;
      call symputx("cvars",cvars);
      call symputx("nvars",nvars);
      call symputx("ncvars",ncvars);
      call symputx("nnvars",nnvars);
    end;
  run;

  %*---------------------------------------------------------------------*
  | Create a JSON key-value pair colleciton for each character variable in 
  | every observation. The API requires the pattern 
  |[{text:value to translate},{text:value to translate}]
  *----------------------------------------------------------------------*;
  filename jbody "%sysfunc(pathname(work))\jbody.json" encoding="UTF-8";

  data _null_;
    length _line $2000;
    set &dsn.(keep=&cvars.) end=eof;
    file jbody;
    array _v[*] &cvars.;
    if _n_=1 then put   '[';
    call missing(line);
    do i = 1 to dim(_v);  
      if ^missing(_v[i]) then do;   
        _line = catx(",",strip(_line), "{'text':"||catx(strip(_v[i]),"'","'}"));
      end;
    end;
    put _line;
    if eof then put ']';
    else put ',';
  run;
  
  filename outjson temp;

  %*---------------------------------------------------------------------*
  | Pass the JSON arguments to the API. Route the response to a temporary
  | file.
  *----------------------------------------------------------------------*;
 
  proc http url="&api/translate?api-version=3.0%nrstr(&from)=&from_lang%nrstr(&to)=&to_lang"
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
  | SAS JSON engine parses JSON response into a SAS dataset
  *----------------------------------------------------------------------*;
  libname jsn JSON fileref=outjson;

  %*---------------------------------------------------------------------*
  | Add ID variable and transpose to restore the original record
  *----------------------------------------------------------------------*;
  data &dsn._trn;
    retain id 1;
    set jsn.translations;
    counter+1;
    if counter>&ncvars. then do;
      id+1;
      counter=1;
    end;
  run;

  proc transpose data=&dsn._trn out=&dsn._trn_t(drop=_name_) prefix=_var;
    by id;
    var text;
  run;
  %*---------------------------------------------------------------------*
  | Find new maximum lengths of the character variables to avoid truncation
  *----------------------------------------------------------------------*;
  proc sql noprint;
    select max(klength(text)) into :len_cvars separated by ' '
    from &dsn._trn
    group by counter;
  quit;

  %*---------------------------------------------------------------------*
  | Recreate the original character variables and lenths and assign the 
  | translated values. Merge with the original data with numeric values 
  | by unique ID 
  *----------------------------------------------------------------------*;
  data &dsn._new(drop=_var: id i);
    %do i = 1 %to &ncvars.;
      length %scan(&cvars,&i,%str( )) $%scan(&len_cvars.,&i.%str( ));
    %end;
    merge &dsn._trn_t
          &dsn._in(keep=id &nvars.);
    by id;
    array cvars[*] &cvars.;
    array vars[*] _var:;
    do i = 1 to dim(vars);
      cvars[i]=vars[i];
    end;
  run;
%mend translate;

%translate( dsn=cm
           ,from_lang=zh-Hans
           ,to_lang=en);
   