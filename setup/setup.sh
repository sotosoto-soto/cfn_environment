#!/usr/bin/env bash

set -e
export AWS_CLI_FILE_ENCODING=UTF-8

if [[ "$#" -lt 2 ]]; then
    echo "エラー: 引数が足りません。"
    echo "使い方: $0 [profile] [up|start|stop|down|create_sshkey]"
    exit 1
fi

PROFILE="$1"
ACTION="$2"

# region、stack_name、key_nameの初期値
REGION="ap-northeast-1"
STACKNAME="cfn-practice-stack"
KEYNAME="cfn-practice-key"   # ← 任意のキーペア名に変更

# スタックに含まれるEC2インスタンスIDを配列INSTANCE_IDSに格納する
get_instance_ids() {
    local ids_text
    ids_text=$(aws cloudformation list-stack-resources \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "StackResourceSummaries[?ResourceType=='AWS::EC2::Instance'].PhysicalResourceId" \
        --output text)

    if [[ -z "$ids_text" || "$ids_text" == "None" ]]; then
        echo "対象のEC2インスタンスが見つかりません。"
        exit 1
    fi

    # 空白・タブ区切りのインスタンスIDを配列に変換
    read -r -a INSTANCE_IDS <<< "$ids_text"
}

# Session Managerでの接続コマンドと、VS Code Remote-SSH用の設定例を表示する
show_connect_command() {
    echo ""
    echo "以下のコマンドでSession Manager経由で接続できます。"
    echo "※ SSMへの登録に数分かかることがあります。"
    echo "-----"
    for id in "${INSTANCE_IDS[@]}"; do
        echo "aws ssm start-session --target $id --region $REGION --profile $PROFILE"
    done
    echo "-----"
    echo ""
    echo "VS Code Remote-SSH用の ~/.ssh/config 設定例:"
    echo "-----"
    for id in "${INSTANCE_IDS[@]}"; do
        echo "Host cfn-practice-ec2"
        echo "    HostName $id"
        echo "    User ec2-user"
        echo "    IdentityFile ~/.ssh/$KEYNAME.pem"
        echo "    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region $REGION --profile $PROFILE"
    done
    echo "-----"
}

if [[ "$ACTION" == "down" ]]; then
    echo "EC2の削除を行います。"

    # CloudFormationスタックを削除
    aws cloudformation delete-stack \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE"

    aws cloudformation wait stack-delete-complete \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE"

    echo "EC2の削除が完了しました。"

elif [[ "$ACTION" == "up" ]]; then
    echo "EC2の作成を行います。"

    # CloudFormationでEC2を作成（IAMロールを含むためcapabilitiesが必要）
    aws cloudformation deploy \
        --template-file "./setup/setup.yml" \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides KeyName="$KEYNAME"

    # インスタンスIDを取得
    get_instance_ids

    echo "EC2 Instance ID: ${INSTANCE_IDS[*]}"
    echo "EC2の作成が完了しました。"
    show_connect_command

elif [[ "$ACTION" == "start" ]]; then
    echo "EC2の起動を行います。"

    get_instance_ids

    echo "起動対象: ${INSTANCE_IDS[*]}"

    aws ec2 start-instances \
        --instance-ids "${INSTANCE_IDS[@]}" \
        --region "$REGION" \
        --profile "$PROFILE"

    echo "EC2インスタンスの起動を待っています..."

    aws ec2 wait instance-running \
        --instance-ids "${INSTANCE_IDS[@]}" \
        --region "$REGION" \
        --profile "$PROFILE"

    echo "EC2インスタンスを起動しました。"
    show_connect_command

elif [[ "$ACTION" == "stop" ]]; then
    echo "EC2の停止を行います。"

    get_instance_ids

    echo "停止対象: ${INSTANCE_IDS[*]}"

    aws ec2 stop-instances \
        --instance-ids "${INSTANCE_IDS[@]}" \
        --region "$REGION" \
        --profile "$PROFILE"

    echo "EC2インスタンスの停止を待っています..."

    aws ec2 wait instance-stopped \
        --instance-ids "${INSTANCE_IDS[@]}" \
        --region "$REGION" \
        --profile "$PROFILE"

    echo "EC2インスタンスを停止しました。"

elif [[ "$ACTION" == "create_sshkey" ]]; then
    echo "SSH鍵の作成を行います。"

    KEYFILE="$HOME/.ssh/$KEYNAME.pem"

    if [[ -e "$KEYFILE" ]]; then
        echo "エラー: $KEYFILE は既に存在します。"
        exit 1
    fi

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if ! aws ec2 create-key-pair \
        --key-name "$KEYNAME" \
        --key-type rsa \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'KeyMaterial' \
        --output text > "$KEYFILE"; then
        rm -f "$KEYFILE"
        echo "エラー: SSH鍵の作成に失敗しました。同名のキーペアが既にAWSにある可能性があります。"
        exit 1
    fi

    chmod 400 "$KEYFILE"

    echo "SSH鍵の作成が完了しました。"
    echo "秘密鍵は $KEYFILE です。"

else
    echo "エラー: 第2引数は [up|start|stop|down|create_sshkey] を指定してください。"
    exit 1
fi